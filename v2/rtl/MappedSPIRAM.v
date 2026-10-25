// =============================================================================
// MappedSPIRAM — controlador de RAM SPI (FRAM FM25V02) para femto_UN, v2
//
// Cambios respecto a la v1 (ver docs/CHANGES.md):
//   R1  Lectura de los 32 bits completos, muestreando MISO en el flanco de
//       subida de SCK (mismo esquema que MappedSPIFlash, ya validado).
//   R2  Respeta mem_wmask: sb escribe 1 byte, sh 2 bytes, sw 4 bytes.
//   R3  Dirección alineada a palabra; en sb/sh se escribe en el byte exacto.
//   R4  Little-endian: la dirección A guarda el byte bajo de la palabra
//       (mismo orden que la flash), así lb/lh/lbu/lhu leen el byte correcto.
//   R5  SCK solo corre durante una transferencia (quieto en 0 con CS_N alto).
//   R6  Envía WREN (0x06) antes de cada WRITE (0x02), como pide la datasheet:
//       la FM25V02 borra WEL al terminar cada escritura.
//
// Trama de lectura : CS_N=0 | 0x03 | A[23:0] | 4 bytes (A, A+1, A+2, A+3) | CS_N=1
// Trama de escritura: CS_N=0 | 0x06 | CS_N=1 | CS_N=0 | 0x02 | A[23:0] | 1, 2 o 4 bytes | CS_N=1
// SPI modo 0: el esclavo lee MOSI en el flanco de subida; MOSI cambia en bajada.
// =============================================================================

module MappedSPIRAM (
    input  wire        clk,       // reloj del sistema
    input  wire        reset,     // reset, activo en bajo
    input  wire        rd,        // pulso de lectura (1 ciclo)
    input  wire        wr,        // pulso de escritura (1 ciclo)
    input  wire [15:0] address,   // dirección en bytes dentro de la RAM
    input  wire [3:0]  wmask,     // máscara de bytes de la escritura (mem_wmask)
    input  wire [31:0] wdata,     // dato a escribir (carriles de byte del CPU)
    output wire [31:0] rdata,     // dato leído
    output reg         rbusy,     // en 1 mientras se lee
    output reg         wbusy,     // en 1 mientras se escribe

    // Pines SPI de la RAM
    output reg         CLK,       // SCK
    output reg         CS_N,      // chip select, activo en bajo
    output wire        MOSI,
    input  wire        MISO
);

   parameter divisor = 10;        // periodo de SCK = divisor + 1 ciclos de clk

   // Comandos de la FM25V02
   localparam CMD_READ  = 8'h03;
   localparam CMD_WRITE = 8'h02;
   localparam CMD_WREN  = 8'h06;

   // Estados
   localparam IDLE      = 3'd0;   // esperando rd / wr
   localparam SEND_WREN = 3'd1;   // enviando 0x06
   localparam WREN_GAP  = 3'd2;   // CS_N en alto entre WREN y WRITE
   localparam SEND      = 3'd3;   // enviando comando + dirección (+ datos)
   localparam RECEIVE   = 3'd4;   // recibiendo 32 bits (solo lectura)
   localparam DONE      = 3'd5;   // CS_N en alto, fin de la transferencia

   reg  [2:0]  state;
   reg  [63:0] shift_out;         // trama que sale por MOSI (MSB primero)
   reg  [5:0]  snd_bitcount;      // bits que faltan por enviar - 1
   reg  [5:0]  rcv_bitcount;      // bits que faltan por recibir
   reg  [31:0] rcv_data;
   reg         is_write;          // la transferencia en curso es escritura
   reg  [63:0] write_frame;       // trama WRITE preparada mientras va el WREN
   reg  [5:0]  write_bits;        // longitud de la trama WRITE - 1
   reg  [1:0]  gap_count;

   // -------------------------------------------------------------------------
   // Generador de SCK (igual que MappedSPIFlash). Solo corre en los estados de
   // transferencia; en los demás queda en 0 y el contador en reposo.
   //   clk_div      : un ciclo después de cada flanco de bajada -> cambiar MOSI
   //   clk_div_rise : marca el flanco de subida -> muestrear MISO
   // -------------------------------------------------------------------------
   wire sck_run = (state == SEND_WREN) | (state == SEND) | (state == RECEIVE);

   reg  [5:0] div_counter;
   reg        clk_div;
   reg        clk_div_rise;

   always @(negedge clk) begin
      if (!reset || !sck_run) begin
         div_counter  <= 0;
         clk_div      <= 0;
         clk_div_rise <= 0;
         CLK          <= 0;
      end else begin
         clk_div_rise <= (div_counter == divisor/2);
         if (div_counter >= divisor) begin
            clk_div     <= 1;
            div_counter <= 0;
         end else begin
            clk_div     <= 0;
            div_counter <= div_counter + 1;
         end
         if ((div_counter == divisor/2) | (div_counter == divisor))
            CLK <= ~CLK;
      end
   end

   // -------------------------------------------------------------------------
   // Preparación de la escritura según la máscara de bytes.
   // Los bytes van en orden de dirección: carril 0 en A, carril 1 en A+1...
   // -------------------------------------------------------------------------
   reg  [1:0] wr_offset;          // primer byte escrito dentro de la palabra
   reg  [2:0] wr_nbytes;          // cuántos bytes se escriben (1, 2 o 4)

   always @(*) begin
      case (wmask)
         4'b0001: begin wr_offset = 2'd0; wr_nbytes = 3'd1; end
         4'b0010: begin wr_offset = 2'd1; wr_nbytes = 3'd1; end
         4'b0100: begin wr_offset = 2'd2; wr_nbytes = 3'd1; end
         4'b1000: begin wr_offset = 2'd3; wr_nbytes = 3'd1; end
         4'b0011: begin wr_offset = 2'd0; wr_nbytes = 3'd2; end
         4'b1100: begin wr_offset = 2'd2; wr_nbytes = 3'd2; end
         default: begin wr_offset = 2'd0; wr_nbytes = 3'd4; end  // 4'b1111
      endcase
   end

   wire [15:0] base_addr = {address[15:2], 2'b00};            // alineada a palabra
   wire [15:0] wr_addr   = base_addr + {14'd0, wr_offset};
   wire [31:0] wdata_seq = {wdata[7:0], wdata[15:8], wdata[23:16], wdata[31:24]};
   wire [31:0] wr_bytes  = wdata_seq << {wr_offset, 3'b000};   // primer byte arriba

   // -------------------------------------------------------------------------
   // Máquina de estados de la transferencia
   // -------------------------------------------------------------------------
   always @(negedge clk) begin
      if (!reset) begin
         state        <= IDLE;
         CS_N         <= 1'b1;
         rbusy        <= 1'b0;
         wbusy        <= 1'b0;
         is_write     <= 1'b0;
         shift_out    <= 64'd0;
         snd_bitcount <= 6'd0;
         rcv_bitcount <= 6'd0;
         rcv_data     <= 32'd0;
         write_frame  <= 64'd0;
         write_bits   <= 6'd0;
         gap_count    <= 2'd0;
      end else begin
         case (state)

            IDLE: begin
               CS_N <= 1'b1;
               if (wr) begin                       // escritura: primero WREN
                  CS_N         <= 1'b0;
                  wbusy        <= 1'b1;
                  is_write     <= 1'b1;
                  shift_out    <= {CMD_WREN, 56'd0};
                  snd_bitcount <= 6'd7;
                  write_frame  <= {CMD_WRITE, 8'h00, wr_addr, wr_bytes};
                  write_bits   <= 6'd31 + {wr_nbytes, 3'b000};  // 32 + 8n - 1
                  state        <= SEND_WREN;
               end else if (rd) begin              // lectura
                  CS_N         <= 1'b0;
                  rbusy        <= 1'b1;
                  is_write     <= 1'b0;
                  shift_out    <= {CMD_READ, 8'h00, base_addr, 32'd0};
                  snd_bitcount <= 6'd31;
                  state        <= SEND;
               end
            end

            SEND_WREN: begin
               if (clk_div) begin
                  if (snd_bitcount == 0) begin
                     CS_N      <= 1'b1;              // termina el WREN
                     gap_count <= 2'd3;
                     state     <= WREN_GAP;
                  end else begin
                     snd_bitcount <= snd_bitcount - 6'd1;
                     shift_out    <= {shift_out[62:0], 1'b0};
                  end
               end
            end

            WREN_GAP: begin                          // CS_N alto unos ciclos
               if (gap_count == 0) begin
                  CS_N         <= 1'b0;
                  shift_out    <= write_frame;
                  snd_bitcount <= write_bits;
                  state        <= SEND;
               end else
                  gap_count <= gap_count - 2'd1;
            end

            SEND: begin
               if (clk_div) begin
                  if (snd_bitcount == 0) begin
                     if (is_write)
                        state <= DONE;               // datos ya enviados
                     else begin
                        rcv_bitcount <= 6'd32;
                        state        <= RECEIVE;
                     end
                  end else begin
                     snd_bitcount <= snd_bitcount - 6'd1;
                     shift_out    <= {shift_out[62:0], 1'b0};
                  end
               end
            end

            RECEIVE: begin
               if (clk_div_rise) begin
                  rcv_data <= {rcv_data[30:0], MISO};
                  if (rcv_bitcount == 1)
                     state <= DONE;
                  else
                     rcv_bitcount <= rcv_bitcount - 6'd1;
               end
            end

            DONE: begin                              // rdata ya es válido
               CS_N  <= 1'b1;
               rbusy <= 1'b0;
               wbusy <= 1'b0;
               state <= IDLE;
            end

            default: state <= IDLE;

         endcase
      end
   end

   assign MOSI = shift_out[63];

   // Los bytes llegan en orden de dirección (A primero): se reordenan para que
   // el byte de la dirección A quede en el carril 0, igual que en la flash.
   assign rdata = {rcv_data[7:0], rcv_data[15:8], rcv_data[23:16], rcv_data[31:24]};

endmodule

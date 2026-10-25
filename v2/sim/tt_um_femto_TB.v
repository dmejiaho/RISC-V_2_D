`timescale 1ns / 1ps
module tt_um_femto_TB();
// Testbench uses a 10 MHz clock
// Want to interface to 115200 baud UART
// 25000000 / 115200 = 217 Clocks Per Bit.
parameter tck              = 40;
parameter c_BIT_PERIOD     = 8680;
wire VPWR = 1'b1;
wire VGND = 1'b0;

  reg  CLK;
  reg  i;
  reg  RESET; 
  wire LEDS;
  reg  RXD = 1'b0;
  reg  interrupt_request = 1'b0;

  wire TXD;
  wire spi_cs;
  wire spi_clk;
  wire spi_miso;
  wire spi_mosi;
  wire spi_cs_n_ram;
  wire spi_clk_ram;
  wire spi_miso_ram;
  wire spi_mosi_ram;
  wire ena = 1'b1;      // diseño habilitado, como en el chip real
  wire reset_n = 1'b1;  // VDD siempre alimentado


tt_um_femto uut(
    .clk    (CLK),
    .ena    (ena),
    .rst_n  (RESET),
`ifndef BENCH
    .VPWR   (VPWR),
    .VGND   (VGND),
`endif
    .ui_in  ({4'b0000, interrupt_request, RXD, spi_miso_ram, spi_miso}),
    .uo_out ({TXD, LEDS, spi_clk, spi_clk_ram, spi_cs_n_ram, spi_cs, spi_mosi_ram, spi_mosi}));


  // Takes in input byte and serializes it 
  task UART_WRITE_BYTE;
    input [7:0] i_Data;
    integer     ii;
    begin

      // Send Start Bit
      RXD <= 1'b0;
      #(c_BIT_PERIOD);
      #1000;
      // Send Data Byte
      for (ii=0; ii<8; ii=ii+1)
        begin
          RXD <= i_Data[ii];
          #(c_BIT_PERIOD);
        end

      // Send Stop Bit
      RXD <= 1'b1;
      #(c_BIT_PERIOD);
     end
  endtask // UART_WRITE_BYTE

 spiflash flash0(
	.csb(spi_cs),
	.clk(spi_clk),
	.io0(spi_mosi), // MOSI
	.io1(spi_miso) // MISO
);


  FRAM_SPI flashram0(
   .CSB(spi_cs_n_ram),     // Chip Select (activo en bajo)
   .SCK(spi_clk_ram),    // SPI Clock
   .SI(spi_mosi_ram),     // Serial Input (MOSI)
   .SO(spi_miso_ram),     // Serial Output (MISO)
   .VDD(reset_n),
   .WPB(1'b1)
  );




initial         CLK <= 0;
always #(tck/2) CLK <= ~CLK;


   reg[4:0] prev_LEDS = 0;
   initial begin
	 if(LEDS != prev_LEDS) begin
	    $display("LEDS = %b",LEDS);
	 end
	 prev_LEDS <= LEDS;
	
   end
   
   
       integer idx; 

`ifdef SIM
   // v2: +ram_log guarda en ram_log.txt cada acceso del CPU a la RAM SPI:
   //   tiempo_us  WR 00010100 <- 44332211 mask 1111
   //   tiempo_us  RD 00010100 -> 44332211
   // (va a un archivo para no mezclarse con lo que imprime la UART)
   integer ram_fd = 0;
   initial if ($test$plusargs("ram_log")) begin
     ram_fd = $fopen("ram_log.txt", "w");
     $fdisplay(ram_fd, "# tiempo_us  op  direccion   dato      (mask: bytes escritos)");
   end
   always @(posedge CLK)
     if (ram_fd != 0 && uut.femto0.mapped_spi_ram.wr)
       $fdisplay(ram_fd, "%10.1f  WR  %h <- %h  mask %b", $realtime/1000.0,
                 uut.femto0.mem_address, uut.femto0.mem_wdata, uut.femto0.mem_wmask);
   always @(negedge uut.femto0.spi_ram_rbusy)
     if (ram_fd != 0 && uut.femto0.resetn === 1'b1)
       $fdisplay(ram_fd, "%10.1f  RD  %h -> %h", $realtime/1000.0,
                 uut.femto0.mem_address, uut.femto0.dpram_dout);
`endif

`ifndef BENCH
   // v2: simulación con compuertas (make tt_um_femto). La netlist no tiene el
   // $write de femto.v, así que se decodifica el pin TXD para ver en la
   // terminal lo que imprime el programa.
   // Bit de la UART: 16 * 13 ciclos de reloj (divisor de uart.v con
   // clk_freq = 27 MHz, baud = 115200) = 208 ciclos.
   localparam UART_BIT = 208 * tck;
   integer ub;
   reg [7:0]   uart_char;
   reg [8*80-1:0] uart_line;     // línea en construcción (hasta 80 caracteres)
   integer     uart_n = 0;
   initial begin
     uart_line = 0;
     #1;
     forever begin
       @(negedge TXD);                      // bit de inicio
       #(UART_BIT + UART_BIT/2);            // mitad del primer bit de datos
       for (ub = 0; ub < 8; ub = ub + 1) begin
         uart_char[ub] = TXD;
         #(UART_BIT);
       end
       if (uart_char == 8'h0A) begin        // fin de línea: se imprime completa
         $display("[%7.3f ms] UART: %0s", $realtime/1000000.0, uart_line);
         uart_line = 0; uart_n = 0;
       end else if (uart_char >= 8'h20 && uart_char < 8'h7F && uart_n < 80) begin
         uart_line = {uart_line[8*79-1:0], uart_char};
         uart_n = uart_n + 1;
       end
     end
   end

   // Avance de la simulación (las compuertas simulan mucho más lento que el
   // RTL): un aviso por cada 1 ms de tiempo simulado.
   initial forever begin
     #(1000000);
     $display("[%7.3f ms] simulando...", $realtime/1000000.0);
   end
`endif

   // v2: +tiempo_ms=N alarga la simulación a N ms (para firmware largo).
   // Sin el argumento, termina como en la v1.
   integer tiempo_ms = 0;
   initial begin
     if ($value$plusargs("tiempo_ms=%d", tiempo_ms) && tiempo_ms > 0) begin
       #(tiempo_ms * 1000000.0);   // timescale 1 ns
       $display("\n[TB] fin por tiempo: %0d ms", tiempo_ms);
       $finish;
     end
   end

   initial begin

    $dumpfile("tt_um_femto_TB.vcd");
`ifdef SIM
    $dumpvars(0, uut);                      // RTL: todo el diseño
`else
    // Compuertas: por defecto solo el nivel de la netlist (pines y cables,
    // ~11 mil señales). Con +vcd_completo también el interior de cada celda,
    // como el Makefile del curso (~150 mil señales, ~1 GB por ms simulado).
    if ($test$plusargs("vcd_completo")) $dumpvars(0, uut);
    else                                $dumpvars(1, uut);
`endif
    $dumpvars(1, tt_um_femto_TB);           // v2: reloj, reset, TXD y buses SPI
    $dumpvars(1, flash0);
    $dumpvars(1, flashram0);                // v2: pines del chip de RAM
`ifdef SIM
    for(idx = 0; idx < 32; idx = idx +1)  $dumpvars(0, tt_um_femto_TB.uut.femto0.CPU.registerFile[idx]);
    for(idx = 0; idx < 64; idx = idx +1)  $dumpvars(0, tt_um_femto_TB.flashram0.mem[idx]);
`endif
    // v2: zona usada por test_ram_bytes.S (0x100 - 0x10B). Está en el modelo
    // de la RAM (fuera del chip), así que también se ve con la netlist.
    for(idx = 256; idx < 268; idx = idx +1)  $dumpvars(0, tt_um_femto_TB.flashram0.mem[idx]);

    #0   RXD   = 1;
    #0   RESET = 0;
    #80  RESET = 0;
  #160 RESET = 1;


    for (idx=0; idx<20; idx=idx+1) begin
      @(posedge CLK);
      interrupt_request = 1;
      @(posedge CLK);
      interrupt_request = 0;
      repeat (400)  @(posedge CLK);
    end 
    #(tck*100000)
    UART_WRITE_BYTE(8'h38);
    #(tck*8000)

    UART_WRITE_BYTE(8'h2A);    // Operator *
    #(tck*8000)   

    UART_WRITE_BYTE(8'h39);
    #(tck*120000)

    UART_WRITE_BYTE(8'h38);
    #(tck*8000)

    UART_WRITE_BYTE(8'h2A);    // Operator *
    #(tck*8000)   

    UART_WRITE_BYTE(8'h37);
    #(tck*8000)

//    @(posedge CLK);
    #(tck*200000);
    if (tiempo_ms == 0) $finish;   // duración original (~19 ms)
 end

endmodule


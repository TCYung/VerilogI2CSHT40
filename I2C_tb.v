`timescale 1ns/1ps

module I2C_TB;
    reg [6:0] Address;
    reg [7:0] Data_Frames;
    reg rw;
    reg processor;

    wire [3:0] shtreads, bytesreceived, outputreceivedcounter;
    wire [2:0] masterstateout;
    wire [7:0] datareceived;
    wire [15:0] tempoutput, rhoutput;
    
    clock_gen testclk1 (clk);
    
    i2c_master master1 (
        .clk (clk), 
        .Sda_Data(Sda_Data), 
        .Processor_Ready(processor), 
        .Command_Data_Frames(Data_Frames),
        .Peripheral_Address(Address),
        .Scl_Data(Scl_Data),
        .i2c_writes(i2c_writes),
        .SHT_Reads(shtreads),
        .CRC_Error(CRC_Error),
        .Bytes_Received(bytesreceived),
        .Data_Received(datareceived),
        .Output_Received_Counter(outputreceivedcounter),
        .Frames_Read(Frames_Read),
        .Master_State_Out(masterstateout),
        .r_or_w(rw)
        
        );
    i2c_sht40 peripheral1 (
        .clk (clk),
        .Output_Received_Counter(outputreceivedcounter), 
        .Data_Received(datareceived), 
        .SHT_Reads(shtreads), 
        .Temperature_Output(tempoutput), 
        .Humidity_Output(rhoutput),
        .Temp_Ready_Out(Temp_Ready_Out),
        .RH_Ready_Out(RH_Ready_Out)
        );
    i2c_scl scl1 (
        .clk(clk),
        .Scl_Data(Scl_Data),
        .Sda_Data(Sda_Data),
        .Master_State_Out(masterstateout)
    );

    // task test_1(); begin
    //     #10 test_tx_ena <= 1;
    //     test_load = 9'b111100111;
    //     end
    // endtask

    //always @(posedge clk) begin

    //end



    initial begin
        Address = 7'b1010101;
        Data_Frames = 8'b10101010;
        rw = 1'b1;
        processor = 1'b1;


    //     //test_1();

    //     test_load = 9'b111100111;
    //     test_tx_ena = 1; 
    //     counter = 0;
    end
    
    pullup SCL (Scl_Data);
    pullup SDA (Sda_Data);

endmodule

module clock_gen (output reg clk);
    initial begin
        clk = 0;
    end
    
    always begin
        #1 clk = ~clk;
        
    end
endmodule
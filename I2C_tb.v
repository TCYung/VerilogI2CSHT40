`timescale 1ns/1ps

module I2C_TB;
    reg [6:0] Address;
    reg [7:0] Data_Frames;
    reg rw;
    reg processor;
    reg writes;

    wire [3:0] shtreads, bytesreceived, outputreceivedcounter;
    wire [2:0] masterstateout;
    wire [7:0] datareceived;
    wire [15:0] tempoutput, rhoutput;
    wire [2:0] sclstateout;
    
    clock_gen testclk1 (clk);

    sht_tb sht_tb1 (
        .clk (clk),
        .Master_State_Out(masterstateout),
        .Sda_Data(Sda_Data),
        .Scl_Data(Scl_Data),
        .Scl_State_Out(sclstateout),
        .Output_Received_Counter(outputreceivedcounter)
        );
    
    i2c_master master1 (
        .clk (clk), 
        .Sda_Data(Sda_Data), 
        .Processor_Ready(processor), 
        .Command_Data_Frames(Data_Frames),
        .Peripheral_Address(Address),
        .Scl_Data(Scl_Data),
        .i2c_writes(writes),
        .SHT_Reads(shtreads),
        .Bytes_Received(bytesreceived),
        .Data_Received(datareceived),
        .Output_Received_Counter(outputreceivedcounter),
        .Master_State_Out(masterstateout),
        .Scl_State_Out(sclstateout),
        .CRC_Error_Out(CRC_Error_Out)
        
        );
    i2c_sht40 peripheral1 (
        .clk (clk),
        .Output_Received_Counter(outputreceivedcounter), 
        .Data_Received(datareceived), 
        .SHT_Reads(shtreads), 
        .Temperature_Output(tempoutput), 
        .Humidity_Output(rhoutput),
        .Temp_Ready_Out(Temp_Ready_Out),
        .RH_Ready_Out(RH_Ready_Out),
        .CRC_Error_Out(CRC_Error_Out)
        );
    i2c_scl scl1 (
        .clk(clk),
        .Scl_Data(Scl_Data),
        .Sda_Data(Sda_Data),
        .Master_State_Out(masterstateout),
        .Scl_State_Out(sclstateout)
    );

    initial begin
        Address = 7'b1000100; //0x44 in hex
        Data_Frames = 8'b11111101; //0xfd in hex
        processor = 1'b1;
        writes = 1'b1;
    end
    
    //we are going to use an always block to simulate the processor and maybe also the peripheral? pretty much just any external inputs to the program
    //once the write process finishes i want to change it to the read state
    //might have to change the processor ready to 0?

    //use scl edge checker so that sda switches during the falling edge and holds it until the next falling edge 
    //make sure to release the line after the 8th transmission so that the master can ack 
    //start with making sure that one byte transmission works and that acks and waveforms look fine

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

module sht_tb (input clk, inout Sda_Data, input [2:0] Master_State_Out, input Scl_Data, input [2:0] Scl_State_Out, input [3:0] Output_Received_Counter);
    reg sdadatalocal;
    reg sdaflag; 
    reg scledgechecker;
    reg [3:0] Counter; 
    reg [4:0] tbcounter;
    reg [7:0] tboutdata;
    reg tbfinishflag;

    initial begin
        sdadatalocal = 1'bZ;
        scledgechecker = 1'b0;
        Counter = 4'd0;
        tbcounter = 5'd8;
        tboutdata = 8'b10111110; //0xbe
        tbfinishflag = 1;
    end

    assign Sda_Data = sdadatalocal;

    always @(posedge clk) begin
        case (Output_Received_Counter) 
            1: begin
                tboutdata <= 8'b11101111;
                if (tbfinishflag == 0 && tboutdata !== 8'b11101111) begin
                    tbcounter <= 8;
                    tbfinishflag <= 1;
                end
            end
            2: begin
                tboutdata <= 8'b10010010;
                if (tbfinishflag == 0 && tboutdata !== 8'b10010010) begin
                    tbcounter <= 8;
                    tbfinishflag <= 1;
                end
            end
            3: begin
                tboutdata <= 8'b10101011;
                if (tbfinishflag == 0 && tboutdata !== 8'b10101011) begin
                    tbcounter <= 8;
                    tbfinishflag <= 1;
                end
            end
            4: begin
                tboutdata <= 8'b11001101;
                if (tbfinishflag == 0 && tboutdata !== 8'b11001101) begin
                    tbcounter <= 8;
                    tbfinishflag <= 1;
                end
            end
            5: begin
                tboutdata <= 8'b01101111;
                if (tbfinishflag == 0 && tboutdata !== 8'b01101111) begin
                    tbcounter <= 8;
                    tbfinishflag <= 1;
                end
            end
        endcase

        if (Master_State_Out == 3'b010 || Master_State_Out == 3'b100 || Counter > 4'd7) begin
            scledgechecker <= Scl_Data;
            if (scledgechecker && !Scl_Data) begin
                Counter <= Counter + 4'd1;
            end 
            if (Counter == 4'd8) begin
                sdadatalocal <= 1'b0; 
            end
            if (Counter == 4'd9) begin
                sdadatalocal <= 1'bZ;
                Counter <= 4'd0;
            end               
        end
        if (Master_State_Out == 3'b011 && Scl_State_Out == 3'b001) begin
            scledgechecker <= Scl_Data;
            if (scledgechecker && !Scl_Data) begin
                tbcounter <= tbcounter - 5'd1;
            end
            if (tboutdata[tbcounter-4'd1] == 1'b0 && tbcounter > 4'd0) begin
                sdadatalocal <= 1'b0;
            end
            if (tboutdata[tbcounter-4'd1] == 1'b1 && tbcounter > 4'd0) begin
                sdadatalocal <= 1'bZ;
            end
            if (tbcounter == 0 && tbfinishflag) begin
                tbcounter <= 4'd0;
                tbfinishflag <= 0;
                sdadatalocal <= 1'bZ;
            end
            
        end
    end 
endmodule
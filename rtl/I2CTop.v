module I2C_Top
    (
        inout Sda_Data,
        inout Scl_Data,
        input clk,
        input processor, //comment out when TB

        output [15:0] m_axis_tdata,
        output m_axis_tvalid,
        input m_axis_tready    

        //uncomment when TB
    //    output [3:0] outputreceivedcountertb,
    //    output [2:0] masterstateouttb,
    //    output [2:0] sclstateouttb
    );
    reg [6:0] Address;
    reg [7:0] Data_Frames;
    reg rw;
    //reg processor; //uncomment when TB
    reg writes;

    wire [3:0] shtreads, bytesreceived, outputreceivedcounter;
    wire [2:0] masterstateout;
    wire [7:0] datareceived;
    wire [15:0] tempoutput, rhoutput;
    wire tempreadyout, rhreadyout;
    wire [2:0] sclstateout;
    
    assign outputreceivedcountertb = outputreceivedcounter;
    assign masterstateouttb = masterstateout;
    assign sclstateouttb = sclstateout; 

    wire Sda_Out;
    wire Scl_Out;

    assign Sda_Data = Sda_Out ? 1'bZ : 0;
    assign Scl_Data = Scl_Out ? 1'bZ : 0;

    wire Sda_In;
    wire Scl_In;

    assign Sda_In = Sda_Data;
    assign Scl_In = Scl_Data;

    assign m_axis_tvalid = (rhreadyout || tempreadyout) && m_axis_tready;
    assign m_axis_tdata = rhreadyout ? rhoutput : (tempreadyout ? tempoutput : 0);

    i2c_master master1 (
        .clk (clk), 
        .Sda_Out(Sda_Out), 
        .Sda_In(Sda_In), 
        //.Processor_Ready(processor), //uncomment when tb
        .Processor_Ready(~processor), //comment when TB
        .Command_Data_Frames(Data_Frames),
        .Peripheral_Address(Address),
        .Scl_Out(Scl_Out),
        .i2c_writes(writes),
        .SHT_Reads(shtreads),
        .Bytes_Received(bytesreceived),
        .Data_Received(datareceived),
        .Output_Received_Counter(outputreceivedcounter),
        .Master_State_Out(masterstateout),
        .Scl_State_Out(sclstateout),
        .CRC_Error_Out(CRC_Error_Out),
        .Scl_Flag_Out(Scl_Flag_Out)
        
        );
    i2c_sht40 peripheral1 (
        .clk (clk),
        .Output_Received_Counter(outputreceivedcounter), 
        .Data_Received(datareceived), 
        .SHT_Reads(shtreads), 
        .Temperature_Output(tempoutput), 
        .Humidity_Output(rhoutput),
        .Temp_Ready_Out(tempreadyout),
        .RH_Ready_Out(rhreadyout),
        .CRC_Error_Out(CRC_Error_Out)
        );
    i2c_scl scl1 (
        .clk(clk),
        .Scl_Out(Scl_Out),
        .Sda_In(Sda_In),
        .SHT_Reads(shtreads), 
        .Output_Received_Counter(outputreceivedcounter), 
        .Master_State_Out(masterstateout),
        .Scl_State_Out(sclstateout),
        .Scl_Flag_Out(Scl_Flag_Out)
    );

    initial begin
        Address = 7'b1000100; //0x44 in hex
        Data_Frames = 8'b11100000; //0xE0 in hex
        //processor = 1'b1; //uncomment when TB
        writes = 1'b1;
    end

endmodule

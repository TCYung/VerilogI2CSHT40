module i2c_sht40
    (
        input clk,
        input [3:0] Output_Received_Counter,
        input [7:0] Data_Received, 
        output [3:0] SHT_Reads,
        output [15:0] Temperature_Output,
        output [15:0] Humidity_Output,
        output Temp_Ready_Out, RH_Ready_Out,
        output CRC_Error_Out
    );

    parameter SHT_Initial = 3'b000;
    parameter SHT_1 = 3'b001;
    parameter SHT_2 = 3'b010;
    parameter SHT_3 = 3'b011;


    wire Sht_Writes;
    wire [2:0] Sht_Reads;
    wire [1:0] Sht_Checksum;
    
    wire [5:0] Poly;
    reg [7:0] Temp_CRC; 
    reg [2:0] SHT_State;

    reg CRC_Error;
    
    reg SHT1_Counter;
    reg SHT2_Counter;
    
    reg Temp_Ready, RH_Ready;
    reg [15:0] Temperature, Humidity;

    reg [3:0] CRC_Counter;

    reg SHT1_Flag, SHT2_Flag; 

    assign Sht_Writes = 1'b1; //there is 1 write after the address
    assign Sht_Checksum = 2'd3; //every third read is a checksum that needs to be verified 

    assign Poly = 6'b110001; //0x31 in binary used to xor the temp crc

    assign SHT_Reads = 4'd5;
    
    assign Temperature_Output = Temperature;
    assign Humidity_Output = Humidity;
    
    assign Temp_Ready_Out = Temp_Ready;
    assign RH_Ready_Out = RH_Ready;

    assign CRC_Error_Out = CRC_Error;
    
    initial begin
        SHT_State = SHT_Initial;
        CRC_Error = 1'b0;
        SHT1_Counter = 1'b0;
        SHT2_Counter = 1'b0;
        CRC_Counter = 4'd0;
        SHT1_Flag = 0;
        SHT2_Flag = 0;
        RH_Ready = 0;
        Temp_Ready = 0;
    end

    always @(posedge clk) begin

        case (SHT_State)
            SHT_Initial: begin
                CRC_Error <= 0;

                // if (Output_Received_Counter == 0) begin 
                    
                // end
                if (Output_Received_Counter == 1) begin 
                    SHT_State <= SHT_1;
                    RH_Ready <= 0;
                end

                if (Output_Received_Counter == 4) begin 
                    Temp_Ready <= 0;
                    SHT_State <= SHT_1;
                end
            end
            
            SHT_1: begin
                //assign first byte of temp if 4'd1 or first byte of RH if 4'd4
                if (Output_Received_Counter == 1 && ~SHT1_Flag) begin
                    Temperature[15:8] <= Data_Received;
                    SHT1_Flag <= 1;
                end
                if (Output_Received_Counter == 4 && ~SHT1_Flag) begin
                    Humidity[15:8] <= Data_Received;
                    SHT1_Flag <= 1;
                end
                
                if (~SHT1_Counter) begin //runs code only once
                    Temp_CRC <= (8'b11111111 ^ Data_Received); 
                    SHT1_Counter <= 1;
                end  
                
                if (CRC_Counter < 8 && SHT1_Counter) begin
                    CRC_Counter <= CRC_Counter + 1;
                    if (Temp_CRC[7] == 1'b0) begin
                        Temp_CRC <= {Temp_CRC[6:0], 1'b0};
                    end
                    else begin
                        Temp_CRC <= {Temp_CRC[6:0], 1'b0} ^ Poly;	
                    end
                end
                    
                if (Output_Received_Counter == 2 || Output_Received_Counter == 5) begin
                    SHT1_Counter <= 0;
                    CRC_Counter <= 0;
                    SHT1_Flag <= 0;
                    SHT_State <= SHT_2; 
                end
                    
            end

            SHT_2: begin
                //assign second byte of temp if 4'd1 or second byte of RH if 4'd4
                if (Output_Received_Counter == 2 && ~SHT2_Flag) begin
                    Temperature[7:0] <= Data_Received;
                    SHT2_Flag <= 1;
                end
                if (Output_Received_Counter == 5 && ~SHT2_Flag) begin
                    Humidity[7:0] <= Data_Received;
                    SHT2_Flag <= 1;
                end

                if (~SHT2_Counter) begin //runs code only once
                    Temp_CRC <= Temp_CRC ^ Data_Received;
                    SHT2_Counter <= 1;
                end

                if (CRC_Counter < 8 && SHT2_Counter) begin
                    CRC_Counter <= CRC_Counter + 1;
                    if (Temp_CRC[7] == 0) begin
                        Temp_CRC <= {Temp_CRC[6:0], 1'b0};
                    end
                    else begin
                        Temp_CRC <= {Temp_CRC[6:0], 1'b0} ^ Poly;	
                    end
                end

                if (Output_Received_Counter == 3 || Output_Received_Counter == 0) begin
                    SHT2_Counter <= 0;
                    CRC_Counter <= 0;
                    SHT2_Flag <= 0;
                    SHT_State <= SHT_3; 
                end              
            end

            SHT_3: begin //the master module uses the SHT_Reads so once it reaches 5 it will go to end state 
                if (Temp_CRC == Data_Received) begin
                    if (Output_Received_Counter == 3) begin
                        Temp_Ready <= 1;
                        SHT_State <= SHT_Initial;
                    end
                    if (Output_Received_Counter == 0) begin
                        RH_Ready <= 1;
                        SHT_State <= SHT_Initial;
                    end            
                end

                if (Temp_CRC !== Data_Received) begin //error stops the transmission and is supposed to restart it
                    CRC_Error <= 1;
                    SHT_State <= SHT_Initial;
                end
            end
        endcase
    end
endmodule
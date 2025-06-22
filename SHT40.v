module i2c_sht40
    (
        input clk,
        input [3:0] Output_Received_Counter;
        input [6:0] Data_Received;
        output [3:0] SHT_Reads;
    );

    parameter SHT_Initial = 3'b000;
    parameter SHT_1 = 3'b001;
    parameter SHT_2 = 3'b010;
    parameter SHT_3 = 3'b011;


    wire Sht_Writes;
    wire [2:0] Sht_Reads;
    wire [1:0] Sht_Checksum;

    reg [7:0] SHT_Input1; //first input byte
    reg [7:0] SHT_Input2; //second byte
    reg [7:0] SHT_CRC; //crc (third byte)

    reg [5:0] Poly;
    reg [7:0] Temp_CRC; 
    reg [2:0] SHT_State;

    assign Sht_Writes = 1'b1; //there is 1 write after the address
    assign Sht_Reads = 3'd6; //there are 6 reads before master needs to nack and stop the transmission
    assign Sht_Checksum = 2'd3; //every third read is a checksum that needs to be verified 

    assign Poly = 6'b110001; //0x31 in binary used to xor the temp crc

    assign SHT_Reads = 4'd6;

    inital begin
        SHT_State = SHT_Initial;
    end
    always @(posedge clk) begin
        case (SHT_State)
            SHT_Initial: begin
                if (Output_Received_Counter == 4'd1) begin
                    SHT_State <= SHT_1;
                end
            end
            
            SHT_1: begin
                Temp_CRC <= 8'b11111111 ^ SHT_Input1; //need to figure out a way to only run this once, some sort of if statement + counter?

                integer i;

                for (i = 0; i<8; i=i+1) begin
                    if (Temp_CRC[7] == 1'b0) begin
                        Temp_CRC <= {Temp_CRC[6:0], 1'b0};
                    end
                    else begin
                        Temp_CRC <= {Temp_CRC[6:0], 1'b0} ^ Poly;	
                    end
                end
            end

            SHT_2: begin
                Temp_CRC <= Temp_CRC ^ SHT_Input2;

                for (i = 0; i<8; i=i+1) begin
                    if (Temp_CRC[7] == 1'b0) begin
                        Temp_CRC <= {Temp_CRC[6:0], 1'b0};
                    end
                    else begin
                        Temp_CRC <= {Temp_CRC[6:0], 1'b0} ^ Poly;	
                    end
                end
            end

            // SHT_3: begin //below code needs to be fleshed out 
            //     if (Temp_CRC == SHT_CRC) begin
            //         if (# of reads = 3 then continue on) begin
            //             //continue on code
            //         end

            //         else begin
            //             //go to stop case
            //         end
            //     end

            //     else begin
            //         //go to stop state
            //         //output an error bit	
            //     end
            // end
        endcase
    end
endmodule

//master data gets sent here and then it is checked for accuracy, if it is accurate output something to the processor to tell it to read
//if not then have a reset/interupt to tell the master to restart?
//have different registers for temperature and humidity
//depending on the value in the output received value 
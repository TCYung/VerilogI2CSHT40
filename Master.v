module i2c_master //note that SDA has to be high for the whole time that SCL is high to ensure signal integrity
    (input clk,
    inout Sda_Data,
    input Processor_Ready,
    input [6:0] Peripheral_Address,
    input r_or_w, 
    input Scl_Data,
    input i2c_writes, //from peripheral module (how many writes are needed
    input [3:0] SHT_Reads;
    input CRC_Error;
    output [3:0] Bytes_Received
    output [7:0] Data_Received;
    output [3:0] Output_Received_Counter;

    );

    parameter Master_Processor = 3'b000;
    parameter Master_Start = 3'b001;
    parameter Master_Transmit = 3'b010;
    parameter Master_Receive = 3'b011;
    //parameter Master_Ack = 3'b100; //might need this later but it think the acks can just be an if else statement
    //error checking and what to do if no ack can be coded in later
    parameter Master_End = 3'b100;
    
    wire [6:0] Master_Address;
    reg [4:0] Sda_Counter;
    reg [2:0] master_writes;
    reg [2:0] Transmit_Counter;
    reg [2:0] Master_State;
    reg Master_Data;
    reg [2:0] Receive_Counter;
    reg [7:0] Received_Data;
    reg Scl_Edge_Checker;
    reg [3:0] Local_Bytes_Received;
    reg [3:0] Total_Receive_Counter;

    initial begin
        Master_State = Master_Processor;
        Sda_Counter = 5'd0;
        Transmit_Counter = 3'd7;
        Local_Bytes_Received = 4'd0;
        Total_Receive_Counter = 4'd0;
    end

    assign 
    assign Master_Address = Peripheral_Address;
    //assign master_writes = i2c_writes;
    assign Sda_Data = Master_Data;
    assign Bytes_Received = Local_Bytes_Received;
    assign Data_Received = Received_Data;
    assign Output_Received_Counter = Total_Receive_Counter;

    always @(posedge clk) begin
        case(Master_State)

            Master_Processor: begin //the I2C peripheral specific module will give a ready signal and the state will change to start
                if (Processor_Ready == 1'b1) begin
                    Master_State <= Master_Start;
                    master_writes <= i2c_writes; //need to check if this is the right place to put this 
                end
            end

            Master_Start: begin
                Sda_Counter <= Sda_Counter + 1'b1;
                if (Master_Data == 1'b1) begin
                    Master_Data <= 1'b0; //if SCL is high drop SDA so it creates a start instruction
                    if (Sda_Counter == 5'd20) begin //hold the stop for 20 clk cycles to get 20x the 100khz standard transmission speed
                        Master_Data <= 1'bZ;
                        Sda_Counter <= 5'b0;
                        if (r_or_w == 1'b0) begin
                            Master_State <= Master_Transmit;
                        end
                        
                        else begin
                            Master_State <= Master_Receive;
                        end
                    end
                end
            end
            
            
            Master_Transmit: begin 
                if (Sda_Counter < 5'd20) //capping the counter in case it goes out of index and resets back to 0 
                    Sda_Counter <= Sda_Counter + 1'b1;
                if  (Sda_Counter == 5'd20 & Scl_Data == 0) begin //at least 20 clock cycles have to pass along with scl being 0
                    Sda_Counter <= 5'd0;
                    Transmit_Counter <= Transmit_Counter - 3'd1; //starts at 7 which is all the data bits 
                    master_writes <= master_writes - 3'd1; //total number of writes from processor decreases per transmission
                    if (Master_Address[Transmit_Counter] == 1 & Transmit_Counter !== 0) begin //read the address to write to and set sda to be the corresponding bit 
                        Master_Data <= 1'bZ;
                    end
                    else if (Master_Address[Transmit_Counter] == 0 & Transmit_Counter !== 0) begin
                        Master_Data <= 1'b0;
                    end
		
                    else if (Transmit_Counter == 0) begin //after the address is given check if its a read or write command
                        if (r_or_w == 1) begin
                            Master_Data <= 1'b0;
                            Transmit_Counter <= 3'd7; //reset the counter for next time the state is master_transmit
                            //go to write/ack state
                        end
                        else begin
                            Master_Data <= 1'bZ;
                            Transmit_Counter <= 3'd7;
                            Master_State <= Master_Receive;
                            
                        end
                    end		
                end
            end
            
            Master_Receive: begin //some kind of counter that goes to 7 and then gives an ack
                if (Scl_Data == 1 & Receive_Counter < 3'd7) begin //if the SCL line is high the peripheral can transmit data
		            Receive_Counter <= Receive_Counter + 3'd1; //count the number of times data has been transferred
		            Received_Data[Receive_Counter] <= Master_Data; //store the transmitted data with the index that lines up with the counter value
	            end

                if (Receive_Counter == 7 & Scl_Data == 0) begin //if 7 transfers have occurred
                    Master_Data <= 1'b0; //hold the line low once SCL goes to low
                    Scl_Edge_Checker <= Scl_Data;
                    Local_Bytes_Received <= Local_Bytes_Received + 4'd1; 

                    if (Scl_Edge_Checker & ~Scl_Data) begin //falling edge detector, last cycle changed from 1 to 0
                        Master_Data <= 1'bZ;    //the line can be released
                        Receive_Counter <= 3'd0; 
                        Scl_Edge_Checker <= 1'b0; //set edge checker low because high means that an edge has occurred (not 100% sure this works so this might be a point to check)
                        Total_Receive_Counter <= Total_Receive_Counter + 4'd1;

                        if (SHT_Reads == Total_Receive_Counter) begin //after 6 transfers go to the end state
                            Master_Data <= 1'b0;
                            Master_State <= Master_End;
                            Total_Receive_Counter <= 4'd0;
                        end
                    end
                end 

                if (CRC_Error == 1'b1) begin //not 100% sure you would be able to stop right away need to check if i need to wait for a timing
                    Receive_Counter <= 3'd0; //its an interupt so everything should be reset
                    Scl_Edge_Checker <= 1'b0;
                    Total_Receive_Counter <= 4'd0;
                    CRC_Error <= 1'b0;
                    Master_State <= Master_End;
                    Scl_State <= Scl_Stop;
                end

            end

            Master_End: begin
                if (Scl_Data == 1'b1) begin
                    Sda_Data <= 1'bZ; //release high to indicate a stop condition
                    Master_State <= Master_Processor; //unsure if i would need to go back to the processor state or if it should keep looping until there is a signal from the processor to stop it 
                end
            end
        endcase
    end
endmodule

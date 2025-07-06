module i2c_master //note that SDA has to be high for the whole time that SCL is high to ensure signal integrity
    (input clk,
    inout Sda_Data,
    input Processor_Ready,
    input [6:0] Peripheral_Address,
    input [7:0] Command_Data_Frames,

    input r_or_w, 
    input Scl_Data,
    input i2c_writes, //from peripheral module (how many writes are needed)
    input [3:0] SHT_Reads,
    input CRC_Error,
    output [3:0] Bytes_Received,
    output [7:0] Data_Received,
    output [3:0] Output_Received_Counter,

    output Frames_Read,
    output [2:0] Master_State_Out
    );

    parameter Master_Processor = 3'b000;
    parameter Master_Start = 3'b001;
    parameter Master_Transmit = 3'b010;
    parameter Master_Receive = 3'b011;
    parameter Master_Write = 3'b100; 
    parameter Master_Ack = 3'b101;
    parameter Master_End = 3'b110;
    
    //wire [6:0] Master_Address; //tied to peripheral_address
    wire [6:0] Master_Address;
    wire [7:0] Master_Frames; //tied to command_data_frames

    reg [4:0] Sda_Counter;
    reg [2:0] Master_Writes;
    reg [3:0] Transmit_Counter;
    reg [2:0] Master_State;
    reg Master_Data;
    reg [2:0] Receive_Counter;
    reg [7:0] Received_Data;
    reg Scl_Edge_Checker;
    reg [3:0] Local_Bytes_Received;
    reg [3:0] Total_Receive_Counter;
    reg Master_Frames_Read;
    reg Write_Flag;
    reg Ack_Error;

    //testing variable
    //reg r_or_w;
    
    initial begin
        Master_State = Master_Processor; //testing for end state uncomment later
        //Master_State = Master_End; //testing for end state remove later
        Sda_Counter = 5'd0;
        Transmit_Counter = 4'd7; //start at 7-1 = 6 to account for the r/w bit
        Local_Bytes_Received = 4'd0;
        Total_Receive_Counter = 4'd0;
        Write_Flag = 1'b0;
        Master_Frames_Read = 1'b0;
        Ack_Error = 1'b0;
        Master_Data = 1'bZ; //testing for end state uncomment later
        //Master_Data = 1'b0; //testing for end state remove later
        
    end

    assign Master_Address = Peripheral_Address;
    assign Sda_Data = Master_Data;
    assign Bytes_Received = Local_Bytes_Received;
    assign Data_Received = Received_Data;
    assign Output_Received_Counter = Total_Receive_Counter;
    
    assign Frames_Read = Master_Frames_Read;
    assign Master_State_Out = Master_State;

    always @(posedge clk) begin
        case(Master_State)
            //000
            Master_Processor: begin //the I2C peripheral specific module will give a ready signal and the state will change to start
                if (Processor_Ready == 1'b1) begin
                    Ack_Error <= 1'b0;
                    Master_Writes <= i2c_writes; //need to check if this is the right place to put this 
                    Master_State <= Master_Start;
                end
            end

            Master_Start: begin //001
                Sda_Counter <= Sda_Counter + 1'b1;
                if (Sda_Data == 1'b1 || Sda_Counter == 5'd20) begin
                    Master_Data <= 1'b0; //if SCL is high drop SDA so it creates a start instruction
                    if (Sda_Counter == 5'd20) begin //hold the stop for 20 clk cycles to get 20x the 100khz standard transmission speed
                        //Master_Data <= 1'bZ; //leaving the line high would mean an accidental high signal
                        Sda_Counter <= 5'b0;
                        if (r_or_w == 1'b1) begin
                            Master_State <= Master_Transmit;
                        end
                        
                        if (r_or_w == 1'b0) begin
                            Master_State <= Master_Receive;
                        end
                    end
                end
            end
            
            //transmit state when it is = to 6 on the address writing is a bit short compared to the time the transmission stays at the other values
            //might want to check this out later
            
            Master_Transmit: begin //010
                if (Sda_Counter < 5'd20) //capping the counter in case it goes out of index and resets back to 0 
                    Sda_Counter <= Sda_Counter + 1'b1;

                if (Sda_Counter == 5'd20 && Scl_Data == 1'b0) begin //at least 20 clock cycles have to pass along with scl being 0
                    Sda_Counter <= 5'd0;
                    Transmit_Counter <= Transmit_Counter - 4'd1; 
                    
                    //there is a -1 in the counter because i need to be able to access to 0th bit but dont want to have to worry about negative #s
                    if (Master_Address[Transmit_Counter - 4'd1] == 1'b1 && Transmit_Counter !== 4'd0) begin //read the address to write to and set sda to be the corresponding bit 
                        Master_Data <= 1'bZ;
                    end
                    else if (Master_Address[Transmit_Counter - 4'd1] == 1'b0 && Transmit_Counter !== 4'd0) begin
                        Master_Data <= 1'b0;
                    end
                    
                    if (Transmit_Counter == 4'd1) begin //after the address is given check if its a read or write command
                        if (r_or_w == 1'b1) begin //write = 1, read = 0
                            Master_Data <= 1'bZ;
                            Transmit_Counter <= 4'd8; //since this condition goes to the write state that doesnt have a r/w bit it needs = 8-1 = 7
                            Master_State <= Master_Ack;
                        end
                        else begin
                            Master_Data <= 1'bZ;
                            Transmit_Counter <= 4'd7; //receive loops back to the transmit block which means there will be a r/w bit so = 7-1 = 6
                            Master_State <= Master_Receive; 
                        end
                    end		
                end
            end
            
            //looks like the edge checker is working but the simulation doesnt show the edge checker 1 clk cycle behind which is weird 
            Master_Ack: begin //101
                Scl_Edge_Checker <= Scl_Data;
                if (Scl_Edge_Checker && ~Scl_Data && ~Write_Flag) begin //after the falling edge of the write bit command is seen 
                    Master_Data <= 1'bZ; //release the sda line after the scl has gone from 1 to 0 so that the peripheral can ack
                    Write_Flag <= 1'b1; //only run this code once per visit to this state
                    //Write_Flag <= ~Write_Flag;
                end

                if (Write_Flag == 1'b1) begin 
                    if (Scl_Data == 1'b1 && Sda_Data == 1'b0) begin //check if the ack signal is present when the scl is high 
                        Write_Flag <= 1'b0; //reset both "flags"
                        Scl_Edge_Checker <= 1'b0;
                        if (Master_Writes == 3'd0) begin //if the master writes is 0 then all the write commands have finished (end -> processor -> transmit)
                            Master_Frames_Read <= 1'b1;
                            Master_State <= Master_End;
                        end
                        else begin
                            Master_Frames_Read <= 1'b1; //there might need to be a timer for the processor so that it doesnt flip past to the next command before intended
                            Master_State <= Master_Write; 
                        end
                    end

                    // need to make sure the ack error works properly 
                    if (Scl_Data == 1'b1 && Sda_Data == 1'b1) begin
                        Write_Flag <= 1'b0; //reset both "flags"
                        Scl_Edge_Checker <= 1'b0;
                        Ack_Error <= 1'b1;
                        Master_State <= Master_End;
                    end
                end
            end

            Master_Write: begin //100
                Master_Frames_Read <= 1'b0;
                if (Sda_Counter < 5'd20) //capping the counter in case it goes out of index and resets back to 0 
                    Sda_Counter <= Sda_Counter + 1'b1;

                if (Sda_Counter == 5'd20 && Scl_Data == 1'b0) begin //at least 20 clock cycles have to pass along with scl being 0
                    Sda_Counter <= 5'd0;
                    Transmit_Counter <= Transmit_Counter - 4'd1; 
                    
                    //there is a -1 in the counter because i need to be able to access to 0th bit but dont want to have to worry about negative #s
                    if (Master_Frames[Transmit_Counter - 4'd1] == 1'b1 && Transmit_Counter !== 4'd0) begin //read the command frame to write to and set sda to be the corresponding bit 
                        Master_Data <= 1'bZ;
                    end
                    else if (Master_Frames[Transmit_Counter - 4'd1] == 1'b0 && Transmit_Counter !== 4'd0) begin //the !0 means that these two if statements dont run when the counter = 0
                        Master_Data <= 1'b0;
                    end
                    if (Transmit_Counter == 4'd0) begin
                        Master_Writes <= Master_Writes - 4'd1; //total number of writes from processor decreases per transmission 
                        Master_State <= Master_Ack;
                    end
                end
            end
            
            //011
            Master_Receive: begin //some kind of counter that goes to 7 and then gives an ack
                if (Scl_Data == 1 && Receive_Counter < 3'd7) begin //if the SCL line is high the peripheral can transmit data
		            Receive_Counter <= Receive_Counter + 3'd1; //count the number of times data has been transferred
		            Received_Data[Receive_Counter] <= Master_Data; //store the transmitted data with the index that lines up with the counter value
	            end

                if (Receive_Counter == 7 && Scl_Data == 0) begin //if 7 transfers have occurred
                    Master_Data <= 1'b0; //hold the line low once SCL goes to low
                    Scl_Edge_Checker <= Scl_Data;
                    Local_Bytes_Received <= Local_Bytes_Received + 4'd1; 

                    if (Scl_Edge_Checker && ~Scl_Data) begin //falling edge detector, last cycle changed from 1 to 0
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
                    Master_State <= Master_End;
                    //Scl_State <= Scl_Stop;
                end

            end
            //110
            Master_End: begin
                if (Scl_Data == 1'b1) begin
                    Master_Data <= 1'bZ; //release high to indicate a stop condition
                    Master_State <= Master_Processor; //unsure if i would need to go back to the processor state or if it should keep looping until there is a signal from the processor to stop it 
                end
            end
        endcase
    end
endmodule

module i2c_master //note that SDA has to be high for the whole time that SCL is high to ensure signal integrity
    (input clk,
    inout Sda_Data,
    input Processor_Ready,
    input [6:0] Peripheral_Address,
    input [7:0] Command_Data_Frames,

    //this should be internal if we go to the end state it should reset back to write
    //otherwise it should keep looping the repeated start condition 
    //its possible that the peripheral can keep the written instruction and if you are accessing the same peripheral you dont need to rewrite
    //but this is easier for now, can test later on 
    //input r_or_w, 

    input Scl_Data,
    input i2c_writes, //from peripheral module (how many writes are needed)
    input [3:0] SHT_Reads,
    input CRC_Error,
    input [2:0] Scl_State_Out,
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

    parameter Scl_Start = 3'b000;
    parameter Scl_Transmit = 3'b001;
    parameter Scl_Ack = 3'b010;
    parameter Scl_Stop = 3'b011;
    
    //wire [6:0] Master_Address; //tied to peripheral_address
    wire [6:0] Master_Address;
    wire [7:0] Master_Frames; //tied to command_data_frames
    wire Sda_Counter_Ready;
    wire Sda_Falling_Edge;
    wire Sda_Rising_Edge;

    reg [4:0] Sda_Counter;
    reg [2:0] Master_Writes;
    reg [3:0] Transmit_Counter;
    reg [2:0] Master_State;
    reg Master_Data;
    reg [3:0] Receive_Counter;
    reg [7:0] Received_Data;
    reg Scl_Edge_Checker;
    reg [3:0] Local_Bytes_Received;
    reg [3:0] Total_Receive_Counter;
    reg Master_Frames_Read;
    reg Write_Flag;
    reg Ack_Error, Ack_Pass;
    reg Transmit_Counter_Flag;
    reg r_or_w;
    reg Write_State_Flag;
    
    initial begin
        Master_State = Master_Processor; //testing for end state uncomment later
        //Master_State = Master_End; //testing for end state remove later
        Sda_Counter = 5'd0;
        Transmit_Counter = 4'd8; //start at 7-1 = 6 to account for the r/w bit
        Local_Bytes_Received = 4'd0;
        Total_Receive_Counter = 4'd0;
        Write_Flag = 1'b0;
        Master_Frames_Read = 1'b0;
        Ack_Error = 1'b0;
        Master_Data = 1'bZ; //testing for end state uncomment later
        //Master_Data = 1'b0; //testing for end state remove later
        Transmit_Counter_Flag = 1'b0;
        Ack_Pass = 1'b0;
        r_or_w = 1'b0;
        Receive_Counter = 4'd0;
        Write_State_Flag = 1'b0;
    end

    assign Master_Address = Peripheral_Address;
    assign Master_Frames = Command_Data_Frames;
    assign Sda_Data = Master_Data;
    assign Bytes_Received = Local_Bytes_Received;
    assign Data_Received = Received_Data;
    assign Output_Received_Counter = Total_Receive_Counter;
    
    assign Frames_Read = Master_Frames_Read;
    assign Master_State_Out = Master_State;

    assign Sda_Counter_Ready = (Sda_Counter == 20);
    assign Scl_Falling_Edge = (Scl_Edge_Checker && !Scl_Data);
    assign Scl_Rising_Edge = (!Scl_Edge_Checker && Scl_Data);


    always @(posedge clk) begin
        case(Master_State)
            //000
            Master_Processor: begin //the I2C peripheral specific module will give a ready signal and the state will change to start
                if (Processor_Ready) begin
                    Ack_Error <= 0;
                    Master_Writes <= i2c_writes;
                    //maybe some kind of if writes is > 1 it changes the r/w to write state
                    Master_State <= Master_Start;
                end
            end
            
            Master_Start: begin //001
                if (Sda_Counter < 20) begin //capping the counter in case it goes out of index and resets back to 0 
                    Sda_Counter <= Sda_Counter + 1;
                end
                
                Write_State_Flag <= 0;
                if ((Sda_Data || Sda_Counter_Ready) && Scl_State_Out == Scl_Start) begin //this or condition doesnt look right
                    Master_Data <= 1'b0; //if SCL is high drop SDA so it creates a start instruction
                    if (Sda_Counter_Ready) begin //hold the stop for 20 clk cycles to get 20x the 100khz standard transmission speed
                        //Sda_Counter <= 0;
                        Master_State <= Master_Transmit; 
                    end
                end
                
                //for the repeated start condition it resets the counter to keep it in the start state for the whole 20 clk cycles
                //in simulation the start condition looks like it works, the scl pulse is really short but SCL should only go low once 
                //sda is read to also be low
                //then after the pulse the clk cycles are synced and provides the 20 clk cycles for it to register as low 
                if (Scl_State_Out !== Scl_Start && Sda_Counter_Ready) begin
                    Sda_Counter <= 0;
                end
            end
            
            //transmit state when it is = to 6 on the address writing is a bit short compared to the time the transmission stays at the other values
            //might want to check this out later
            
            //workaround written for counter since -4'd1 meant that i was 1 cycle behind (ie first cycle supposed to = 1 but its equaling 0)
            //look into this more to figure out what is actually going on and why i needed to do -4'd2 or any subtraction at all
            //its definitely kinda hard to make sense of the code here since its really convoluted try to simplify it down 
            //code works but want to simplify for readability

            //i think i need to split r/w into a different state, if this works for the read code as well im probably going to leave it alone

            //first bit of the transmission address is getting assigned at the same time that scl goes high, probably will be an issue on physical board 
            //likely will be misread as a start or stop instruction

            Master_Transmit: begin //010 (should probably change this state name to address write)
                if (Sda_Counter < 20) begin //capping the counter in case it goes out of index and resets back to 0 
                    Sda_Counter <= Sda_Counter + 1;
                end
                
                //can try making the counter increment instead of decrement this should solve the issue of 0 and going negative
                //should be doing this for the receiver code

                if (Sda_Counter_Ready && !Scl_Data && Transmit_Counter > 0) begin //at least 20 clock cycles have to pass along with scl being 0
                    Transmit_Counter <= Transmit_Counter - 1; 
                    //there is a -2 in the counter because r/w bit, makes it so that it transitions to ack state at the right time as well as to not access "negative" index

                    if (Master_Address[Transmit_Counter - 2]) begin //read the address to write to and set sda to be the corresponding bit 
                        Master_Data <= 1'bZ;
                        Sda_Counter <= 0;
                    end

                    if (!Master_Address[Transmit_Counter - 2]) begin
                        Master_Data <= 1'b0;
                        Sda_Counter <= 0;
                    end
                end

                if (Transmit_Counter == 0) begin //after the address is given check if its a read or write command
                    if (!Transmit_Counter_Flag) begin
                        Sda_Counter <= 0; //delays moving to ack state 
                        Transmit_Counter_Flag <= 1;
                    end
                    
                    //only need to check transmit counter flag both should go to the ack state 
                    if (Transmit_Counter_Flag) begin //write = 0, read = 1
                        Master_Data <= r_or_w ? 1'bZ : 1'b0;

                        if (Sda_Counter_Ready && !Scl_Data) begin
                            Transmit_Counter <= 8; 
                            Sda_Counter <= 0;
                            Transmit_Counter_Flag <= 0;
                            Master_State <= Master_Ack; 
                        end 
                    end	
                end
            end
            
            Master_Ack: begin //101
                Scl_Edge_Checker <= Scl_Data;

                if (!Scl_Data && !Write_Flag) begin 
                    Master_Data <= 1'bZ; //release the sda line after the scl has gone from 1 to 0 so that the peripheral can ack
                    Write_Flag <= 1; //only run this code once per visit to this state
                end

                // once the line has been released the below code can start checking for an ack
                if (Write_Flag) begin 
                    if (Scl_Data && !Sda_Data) begin //check if the ack signal is present when the scl is high 
                        Ack_Pass <= 1;
                    end

                    // need to make sure the ack error works properly (i dont think it does, it send to end state but doesnt trigger a stop -> restart)
                    //if there is no ack go to the end state and reset the flags
                    if (Scl_Data && Sda_Data) begin
                        Write_Flag <= 0; 
                        Ack_Error <= 1;
                        Master_State <= Master_End;
                    end
                    
                    //if there was a successful ack and scl has just negedged reset all the flags and check if there are more writes 
                    if (Ack_Pass && Scl_Falling_Edge) begin
                        Write_Flag <= 0; 
                        Ack_Pass <= 0;
                        if (Master_Writes == 0) begin //if the master writes is 0 then all the write commands have finished 
                            if (Write_State_Flag == 1) begin
                                //change this to master frames written or something similar read makes it sounds like something was successfully read
                                Master_Frames_Read <= 1; //tell the processor that the write was sucessful and to load in any new write byte
                                Master_State <= Master_Start; //possible to change this to repeated start input
                            end
                            if (Write_State_Flag == 0) begin
                                Master_State <= Master_Receive;
                            end
                        end
                        else begin
                            Master_Frames_Read <= 1; //there might need to be a timer for the processor so that it doesnt flip past to the next command before intended
                            Master_State <= Master_Write; 
                        end
                    end
                end
            end

            Master_Write: begin //100
                Master_Frames_Read <= 0;
                if (Sda_Counter < 20) //capping the counter in case it goes out of index and resets back to 0 
                    Sda_Counter <= Sda_Counter + 1;
                
                if (Sda_Counter_Ready && !Scl_Data && Scl_State_Out == Scl_Transmit) begin //change the value once per clk cycle, scl state checker because scl goes to transmit later than master
                    Sda_Counter <= 0;
                    if (Transmit_Counter !== 0) begin
                        Transmit_Counter <= Transmit_Counter - 1; 
                        //there is a -1 in the counter because i need to be able to access to 0th bit but dont want to have to worry about negative #s
                        if (Master_Frames[Transmit_Counter - 1]) begin //read the command frame to write to and set sda to be the corresponding bit 
                            Master_Data <= 1'bZ;
                        end
                        else if (!Master_Frames[Transmit_Counter - 1]) begin //the !0 means that these two if statements dont run when the counter = 0
                            Master_Data <= 1'b0;
                        end
                    end
                    
                    if (Transmit_Counter == 0) begin
                        Master_Writes <= Master_Writes - 1; //total number of writes from processor decreases per transmission 

                        //need to figure something out later that changes r/w to write state if the processor wants to measure something else
                        if (Master_Writes == 1) begin
                            r_or_w <= 1;
                            Write_State_Flag <= 1; //there is
                        end
                        Transmit_Counter <= 8;
                        Master_State <= Master_Ack;
                    end
                end
            end
            
            //011
            Master_Receive: begin //some kind of counter that goes to 7 and then gives an ack
                Scl_Edge_Checker <= Scl_Data;
                if (Receive_Counter < 8 && Scl_Rising_Edge) begin //if the SCL line is high the peripheral can transmit data
		            Receive_Counter <= Receive_Counter + 1; //count the number of times data has been transferred
		            Received_Data[7-Receive_Counter] <= Sda_Data; //store the transmitted data with the index that lines up with the counter value
	            end

                if (Receive_Counter == 8 && !Scl_Data && !Scl_Falling_Edge) begin //if 7 transfers have occurred
                    Master_Data <= 1'b0; //hold the line low once SCL goes to low
                    Receive_Counter <= Receive_Counter + 1; 

                end

                if (Receive_Counter == 9 && Scl_Falling_Edge) begin //falling edge detector, last cycle changed from 1 to 0
                    Local_Bytes_Received <= Local_Bytes_Received + 1; //this is counting multiple times in a cycle changes need to be made
                    Master_Data <= 1'bZ;    //the line can be released
                    Receive_Counter <= 0; 
                    Total_Receive_Counter <= Total_Receive_Counter + 1;
                    
                    //modifications need to be made for repeated start
                    if (SHT_Reads == Total_Receive_Counter) begin //after 6 transfers go to the end state
                        Master_Data <= 1'b0;
                        Total_Receive_Counter <= 0;
                        Master_State <= Master_End;
                        
                    end
                end

                if (CRC_Error) begin //not 100% sure you would be able to stop right away need to check if i need to wait for a timing
                    Receive_Counter <= 0; //its an interupt so everything should be reset
                    Scl_Edge_Checker <= 0;
                    Total_Receive_Counter <= 0;
                    Master_State <= Master_End;
                    //Scl_State <= Scl_Stop;
                end

            end
            //realized that the nxp i2c standard you can do another start message instead of giving a stop condition
            //there needs to be a signal from the processor to stop the transmission and otherwise it should keep starting and transmitting

            //110
            Master_End: begin
                if (Scl_Data) begin
                    Master_Data <= 1'bZ; //release high to indicate a stop condition
                    r_or_w <= 0;
                    Master_State <= Master_Processor; //unsure if i would need to go back to the processor state or if it should keep looping until there is a signal from the processor to stop it 
                end
            end
        endcase
    end
endmodule

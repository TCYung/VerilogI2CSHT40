module i2c_master //note that SDA has to be high for the whole time that SCL is high to ensure signal integrity
    (input clk,
    output Sda_Out,
    input Sda_In,
    input Processor_Ready,
    input [6:0] Peripheral_Address,
    input [7:0] Command_Data_Frames,

    //this should be internal if we go to the end state it should reset back to write
    //otherwise it should keep looping the repeated start condition 
    //its possible that the peripheral can keep the written instruction and if you are accessing the same peripheral you dont need to rewrite
    //but this is easier for now, can test later on 

    input Scl_Out,
    input i2c_writes, //from peripheral module (how many writes are needed)
    input [3:0] SHT_Reads,
    input CRC_Error_Out,
    input [2:0] Scl_State_Out,
    output [3:0] Bytes_Received,
    output [7:0] Data_Received,
    output [3:0] Output_Received_Counter,

    output [2:0] Master_State_Out,

    input Scl_Flag_Out

    );

    parameter Master_Processor = 3'b000;
    parameter Master_Start = 3'b001;
    parameter Master_Transmit_Address = 3'b010;
    parameter Master_Receive = 3'b011;
    parameter Master_Write = 3'b100; 
    parameter Master_Ack = 3'b101;
    parameter Master_End = 3'b110;

    parameter Scl_Start = 3'b000;
    parameter Scl_Transmit = 3'b001;
    parameter Scl_Ack = 3'b010;
    parameter Scl_Stop = 3'b011;
    
    wire [6:0] Master_Address;
    wire [7:0] Master_Frames; //tied to command_data_frames
    wire Sda_Counter_Ready;
    wire Sda_Falling_Edge;
    wire Sda_Rising_Edge;

    reg [18:0] Processor_Counter;
    reg [8:0] Sda_Counter;
    reg [2:0] Master_Writes;
    reg [3:0] Transmit_Counter;
    reg [2:0] Master_State;
    reg Master_Data;
    reg [3:0] Receive_Counter;
    reg [7:0] Received_Data;
    reg Scl_Edge_Checker;
    reg [3:0] Local_Bytes_Received;
    reg [3:0] Total_Receive_Counter;
    reg Write_Flag;
    reg Ack_Error, Ack_Pass;
    reg Transmit_Counter_Flag;
    reg r_or_w;
    reg Write_State_Flag;
    
    initial begin
        Master_State = Master_Processor; 
        Sda_Counter = 5'd0;
        Transmit_Counter = 4'd0; 
        Local_Bytes_Received = 4'd0;
        Total_Receive_Counter = 4'd0;
        Write_Flag = 1'b0;
        Ack_Error = 1'b0;
        Master_Data = 1'b1;
        Transmit_Counter_Flag = 1'b0;
        Ack_Pass = 1'b0;
        r_or_w = 1'b0;
        Receive_Counter = 4'd0;
        Write_State_Flag = 1'b0;
        Master_Writes = 1;
        Processor_Counter = 0;
    end

    assign Master_Address = Peripheral_Address;
    assign Master_Frames = Command_Data_Frames;
    assign Sda_Out = Master_Data;
    assign Bytes_Received = Local_Bytes_Received;
    assign Data_Received = Received_Data;
    assign Output_Received_Counter = Total_Receive_Counter;
    
    assign Master_State_Out = Master_State;

    assign Sda_Counter_Ready = (Sda_Counter == 480);
    assign Scl_Falling_Edge = (Scl_Edge_Checker && !Scl_Out);
    assign Scl_Rising_Edge = (!Scl_Edge_Checker && Scl_Out);


    always @(posedge clk) begin
        case(Master_State)
            //000
            Master_Processor: begin //the I2C peripheral specific module will give a ready signal and the state will change to start
                Processor_Counter <= Processor_Counter + 1;

                if (Processor_Ready && Processor_Counter > 163200) begin
                    Ack_Error <= 0;
                    Processor_Counter <= 0;
                    Master_State <= Master_Start;
                end
            end
            
            Master_Start: begin //001
                if (Sda_Counter < 480) begin //capping the counter in case it goes out of index and resets back to 0 
                    Sda_Counter <= Sda_Counter + 1;
                end

                Write_State_Flag <= 0;
                if ((Sda_In || Sda_Counter_Ready) && Scl_State_Out == Scl_Start) begin 
                    if (Scl_Out && Sda_Counter_Ready) begin
                        Master_Data <= 0; //if SCL is high drop SDA so it creates a start instruction
                    end

                    if (Sda_Counter_Ready && Scl_Flag_Out) begin 
                        Sda_Counter <= 0;
                        Master_State <= Master_Transmit_Address; 
                    end
                end
                                
                if (Scl_State_Out !== Scl_Start && Sda_Counter_Ready) begin
                    Sda_Counter <= 0;
                end
            end
            
            Master_Transmit_Address: begin //010 
                //8 bits that need to get transfered in this state 
                //you would think < 7 but nonblocking assignment means that i need + 1
                if (!Scl_Out && Transmit_Counter < 8 && Scl_State_Out == Scl_Transmit) begin //only change sda value when scl is low to avoid an accidental start/stop
                    if (Sda_Counter < 480) begin //capping the counter in case it goes out of index and resets back to 0 
                        Sda_Counter <= Sda_Counter + 1;
                    
                        //6- means i can access all 7 data address bits
                        if (Master_Address[6-Transmit_Counter] && Sda_Counter > 240) begin //read the address to write to and set sda to be the corresponding bit 
                            Transmit_Counter <= Transmit_Counter + 1; 
                            Sda_Counter <= 0;
                            Master_Data <= 1;
                        end

                        if (!Master_Address[6-Transmit_Counter] && Sda_Counter > 240) begin
                            Transmit_Counter <= Transmit_Counter + 1; 
                            Sda_Counter <= 0;
                            Master_Data <= 0;
                        end

                        if (Transmit_Counter == 7 && Sda_Counter > 240) begin
                            Transmit_Counter <= Transmit_Counter + 1; 
                            Sda_Counter <= 0;
                        end
                    end        
                end

                if (Scl_Out && Transmit_Counter < 8) begin
                    Sda_Counter <= 0;
                end

                if (Transmit_Counter == 8) begin //after the address is given check if its a read or write command
                    if (!Transmit_Counter_Flag) begin
                        Sda_Counter <= 0; //delays moving to ack state 
                        Transmit_Counter_Flag <= 1;
                    end
                    
                    //sets 8th bit to corresponding r/w
                    if (Transmit_Counter_Flag) begin //write = 0, read = 1
                        if (Sda_Counter < 480) begin //capping the counter in case it goes out of index and resets back to 0 
                            Sda_Counter <= Sda_Counter + 1;
                        end

                        Master_Data <= r_or_w ? 1 : 0;

                        if (Sda_Counter_Ready && !Scl_Out) begin
                            Transmit_Counter <= 0; 
                            Sda_Counter <= 0;
                            Transmit_Counter_Flag <= 0;
                            Master_State <= Master_Ack; 
                        end 
                    end	
                end
            end
            
            Master_Ack: begin //101
                if (!Scl_Out && !Write_Flag) begin 
                    if (Sda_Counter < 480) begin //capping the counter in case it goes out of index and resets back to 0 
                        Sda_Counter <= Sda_Counter + 1;
                    end
                    if (Sda_Counter > 240) begin
                        Master_Data <= 1; //release the sda line after the scl has gone from 1 to 0 so that the peripheral can ack
                        Write_Flag <= 1; //only run this code once per visit to this state
                        Sda_Counter <= 0;
                    end
                end

                // once the line has been released the below code can start checking for an ack
                if (Write_Flag) begin 
                    if (Scl_Out && !Sda_In) begin //check if the ack signal is present when the scl is high 
                        Ack_Pass <= 1;
                    end

                    // need to make sure the ack error works properly (i dont think it does, it send to end state but doesnt trigger a stop -> restart)
                    //if there is no ack go to the end state and reset the flags
                    if (Scl_Out && Sda_In) begin
                        Write_Flag <= 0; 
                        Ack_Error <= 1;
                        Master_State <= Master_End;
                    end
                    
                    //if there was a successful ack check if there are more writes 
                    if (Ack_Pass && Scl_State_Out == Scl_Ack) begin
                        if (Master_Writes == 0) begin //if the master writes is 0 then all the write commands have finished 
                            if (Sda_Counter < 480) begin //capping the counter in case it goes out of index and resets back to 0 
                                Sda_Counter <= Sda_Counter + 1;
                            end

                            if (!Write_State_Flag && Sda_Counter_Ready) begin
                                Sda_Counter <= 0;
                                Write_Flag <= 0; 
                                Ack_Pass <= 0;
                                Master_State <= Master_Receive; 
                            end
                            
                            if (Write_State_Flag && Sda_Counter > 240) begin
                                Sda_Counter <= 0;
                                Write_Flag <= 0; 
                                Ack_Pass <= 0;
                                Master_Data <= 0;
                                Master_State <= Master_End;
                            end
                        end

                        else begin
                            Write_Flag <= 0; 
                            Ack_Pass <= 0;
                            Master_State <= Master_Write; 
                        end
                    end
                end
            end

            //problem that the first transmission is happening while scl is low
            //the restriction that scl has to be in transmit state isnt working properly because SCL is supposed to stay in the ack state for longer
            //this could potentially be solved by solving a different problem where SCL is low for 2 cycles in between address write and instruction write
            //since the pcb design doesnt have the same issue 

            Master_Write: begin //100   

                if (!Scl_Out && Transmit_Counter < 8 && Scl_State_Out == Scl_Transmit) begin //change the value once per clk cycle, scl state checker because scl goes to transmit later than master
                    if (Sda_Counter < 480) begin//capping the counter in case it goes out of index and resets back to 0 
                        Sda_Counter <= Sda_Counter + 1;
                    end
                        if (Transmit_Counter < 8) begin
                            // 7- because all 8 bits are being used for data instead of the address write where 1 bit of the byte was used for r/w
                            if (Master_Frames[7 - Transmit_Counter] && Sda_Counter > 240) begin //read the command frame to write to and set sda to be the corresponding bit 
                                Transmit_Counter <= Transmit_Counter + 1; 
                                Sda_Counter <= 0;
                                Master_Data <= 1;
                            end
                            else if (!Master_Frames[7 - Transmit_Counter] && Sda_Counter > 240) begin 
                                Transmit_Counter <= Transmit_Counter + 1; 
                                Sda_Counter <= 0;
                                Master_Data <= 0;
                            end
                        end

                        if (Transmit_Counter == 7 && Sda_Counter > 240) begin
                            Transmit_Counter <= Transmit_Counter + 1; 
                            Sda_Counter <= 0;
                        end
                    end

                if (Scl_Out && Transmit_Counter < 8) begin
                    Sda_Counter <= 0;
                end

                if (Transmit_Counter == 8) begin

                    if (Sda_Counter < 480) begin//capping the counter in case it goes out of index and resets back to 0 
                        Sda_Counter <= Sda_Counter + 1;
                    end

                    if (Master_Writes == 1) begin //on the last write the code below lets us know that receive can start next time
                        r_or_w <= 1;
                        Write_State_Flag <= 1; //this flag tells ack state whether the next state should be receive or write 
                    end

                    if (Sda_Counter_Ready && !Scl_Out) begin
                        Master_Writes <= Master_Writes - 1; //total number of writes from processor decreases per transmission 
                        Transmit_Counter <= 0;
                        Master_State <= Master_Ack;
                    end
                end
            end
            
            //011
            Master_Receive: begin                                 
                if (Scl_Out) begin
                    Sda_Counter <= 0;
                end

                Scl_Edge_Checker <= Scl_Out;

                if (Receive_Counter < 8 && Scl_Rising_Edge) begin //if the SCL line is high the peripheral can transmit data
		            Receive_Counter <= Receive_Counter + 1; //count the number of times data has been transferred
		            Received_Data[7-Receive_Counter] <= Sda_In; //store the transmitted data with the index that lines up with the counter value
	            end

                //acking code for the peripheral to see that the data has been successfully received
                if (Receive_Counter == 8 && !Scl_Out && !Scl_Falling_Edge) begin 
                    if (Sda_Counter < 480) begin //capping the counter in case it goes out of index and resets back to 0 
                        Sda_Counter <= Sda_Counter + 1;
                    end

                    if (Sda_Counter > 240 && SHT_Reads !== Total_Receive_Counter) begin
                        Master_Data <= 0; 
                        Receive_Counter <= Receive_Counter + 1; 
                        Sda_Counter <= 0;
                    end

                    if (Sda_Counter > 240 && SHT_Reads == Total_Receive_Counter) begin
                        Receive_Counter <= Receive_Counter + 1; 
                        Sda_Counter <= 0;
                    end
                end

                if (Receive_Counter == 9 && !Scl_Out) begin //wait for the last scl pulse to fall before restarting the receive or going to the repeat start state
                    if (Sda_Counter < 480) begin //capping the counter in case it goes out of index and resets back to 0 
                        Sda_Counter <= Sda_Counter + 1;
                    end

                    if (Sda_Counter > 240) begin
                        Local_Bytes_Received <= Local_Bytes_Received + 1; 
                        Master_Data <= 1;    
                        Receive_Counter <= 0; 
                        Total_Receive_Counter <= Total_Receive_Counter + 1;
                        Sda_Counter <= 0;

                        if (SHT_Reads == Total_Receive_Counter) begin //after 6 transfers go to the end state
                            Total_Receive_Counter <= 0;
                            r_or_w <= 0;
                            Master_Writes <= i2c_writes; 
                            Master_State <= Master_End;                         
                        end
                    end                    
                end

                if (CRC_Error_Out) begin //not 100% sure you would be able to stop right away need to check if i need to wait for a timing
                    Receive_Counter <= 0; //its an interupt so everything should be reset
                    Scl_Edge_Checker <= 0;
                    Total_Receive_Counter <= 0;
                    Master_State <= Master_End;
                end

            end
            
            //110
            Master_End: begin
                if (Sda_Counter < 480) begin //capping the counter in case it goes out of index and resets back to 0 
                        Sda_Counter <= Sda_Counter + 1;
                end

                if (Scl_State_Out == Scl_Stop) begin 
                    if (Scl_Out && Sda_Counter_Ready) begin
                        Sda_Counter <= 0;
                        Master_Data <= 1; 
                    end
                end

                if (Scl_State_Out == Scl_Start && Sda_Counter_Ready) begin
                    Sda_Counter <= 0;
                    Master_State <= Master_Processor; 
                end
                                
                if (Scl_State_Out == Scl_Transmit) begin
                    Sda_Counter <= 0;
                end
            end
        endcase
    end
endmodule

module i2c_scl 
    (input clk,
    inout Scl_Data,
    input Sda_Data,
    input [2:0] Master_State_Out,
    output [2:0] Scl_State_Out
    );

    parameter Scl_Start = 3'b000;
    parameter Scl_Transmit = 3'b001;
    parameter Scl_Ack = 3'b010;
    parameter Scl_Stop = 3'b011;

    parameter Master_Processor = 3'b000;
    parameter Master_Start = 3'b001;
    parameter Master_Transmit = 3'b010;
    parameter Master_Receive = 3'b011;
    parameter Master_Write = 3'b100; 
    parameter Master_Ack = 3'b101;
    parameter Master_End = 3'b110;

    reg [2:0] Scl_State;
    reg [4:0] Scl_Counter;
    reg Scl_Data_Local;
    reg Sda_Edge_Checker;
    reg [4:0] Scl_Transmit_Counter;

    assign Scl_Data = Scl_Data_Local;
    assign Scl_State_Out = Scl_State;
    assign Scl_Counter_Ready = (Scl_Counter == 20);

    initial begin
        Scl_Counter = 5'd0;
        Scl_Transmit_Counter = 5'd0;
        Scl_State = Scl_Start; //testing for end state uncomment later
        Scl_Data_Local = 1'bZ; //testing for end state uncomment later
        //Scl_Data_Local = 1'b0; //remove later
        //Scl_State = Scl_Ack; //remove later
    end 

    always @(posedge clk) begin
        case (Scl_State)
            Scl_Start: begin //000
                if (Master_State_Out == Master_Start) begin
                    Scl_Counter <= Scl_Counter + 1;
                    if (!Sda_Data) begin
                        Scl_Data_Local <= 1'b0;
                        if (Scl_Counter_Ready) begin
                            //Scl_Data_Local <= 1'bZ; //leaving the line high would mean an accidental high signal
                            Scl_Counter <= 0;
                            Scl_State <= Scl_Transmit;
                        end
                    end   
                end
            end
            
            Scl_Transmit: begin //001
                if (Scl_Transmit_Counter < 18) begin //the scl flips high to low and low to high 16 total times with 8 "periods"
                    if (Scl_Counter_Ready) begin
                        if (Scl_Data == 1'b1) begin
                            Scl_Data_Local <= 1'b0;
                            Scl_Counter <= 0;
                            Scl_Transmit_Counter <= Scl_Transmit_Counter + 1;
                        end
                        else begin
                            Scl_Data_Local <= 1'bZ;
                            Scl_Counter <= 0;
                            Scl_Transmit_Counter <= Scl_Transmit_Counter + 1;
                        end
                    end
                    else begin
                        Scl_Counter <= Scl_Counter + 1;
                    end
                end

                else begin
                    Scl_Counter <= Scl_Counter + 1;
                    if (Scl_Counter_Ready) begin
                        Scl_Counter <= 0;
                        Scl_Transmit_Counter <= 0; 
                        Scl_State <= Scl_Ack;
                    end
                end
            end
            
            //010
            Scl_Ack: begin //this is the state after the ack pulse where the SCL line is held low until the SDA line goes back low
                Sda_Edge_Checker <= Sda_Data;
                
                if (Master_State_Out == Master_End) begin //double check that master module can go to end on its own/has the right conditions to go to end state
                    Scl_State <= Scl_Stop;
                end
                
                if (Master_State_Out == Master_Start) begin
                    Scl_Data_Local <= 1'bZ;
                    Scl_State <= Scl_Start;
                end
                //the below looks fine in the simulation but might have problems in some edge cases (breaks when first bit of the next transmission is 0)
                //look to change this to be dependent on a variable or on the state that the master module is in 
                else if (Sda_Data || Master_State_Out == Master_Receive) begin //this code should not take priority over the stop state change
                    Scl_State <= Scl_Transmit;
                end
            end
            
            Scl_Stop: begin //011
                Scl_Data_Local <= 1'bZ;
                if (Sda_Data) 
                    Scl_State <= Scl_Start;
            end

        endcase
    end
endmodule
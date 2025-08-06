module i2c_scl 
    (input clk,
    output Scl_Out,
    input Sda_In,
    input [2:0] Master_State_Out,
    output [2:0] Scl_State_Out,
    output Scl_Flag_Out
    );

    parameter Scl_Start = 3'b000;
    parameter Scl_Transmit = 3'b001;
    parameter Scl_Ack = 3'b010;
    parameter Scl_Stop = 3'b011;

    parameter Master_Processor = 3'b000;
    parameter Master_Start = 3'b001;
    parameter Master_Transmit_Address = 3'b010;
    parameter Master_Receive = 3'b011;
    parameter Master_Write = 3'b100; 
    parameter Master_Ack = 3'b101;
    parameter Master_End = 3'b110;

    reg [2:0] Scl_State;
    reg [8:0] Scl_Counter;
    reg Scl_Out_Local;
    reg Sda_Edge_Checker;
    reg [4:0] Scl_Transmit_Counter;
    reg Scl_Flag; 

    wire Scl_Counter_Ready;

    assign Scl_Out = Scl_Out_Local;
    assign Scl_State_Out = Scl_State;
    assign Scl_Counter_Ready = (Scl_Counter == 480);
    assign Scl_Flag_Out = Scl_Flag;

    initial begin
        Scl_Counter = 5'd0;
        Scl_Transmit_Counter = 5'd0;
        Scl_State = Scl_Start;
        Scl_Out_Local = 1; 
        Scl_Flag = 0;
    end 

    always @(posedge clk) begin
        case (Scl_State)
            Scl_Start: begin //000
                if (Master_State_Out == Master_Start) begin
                    if (!Sda_In && !Scl_Flag) begin
                        Scl_Counter <= Scl_Counter + 1;
                        if (Scl_Counter_Ready) begin
                            Scl_Out_Local <= 0;
                            Scl_Counter <= 0;
                            Scl_Flag <= 1;
                        end
                    end
                end
                if (Scl_Flag == 1) begin
                    Scl_Counter <= Scl_Counter + 1;
                    if (Scl_Counter_Ready) begin
                        Scl_Counter <= 0;
                        Scl_Flag <= 0;
                        Scl_State <= Scl_Transmit;
                    end
                end
                
            end
            
            Scl_Transmit: begin //001
                if (Scl_Transmit_Counter < 18) begin //the scl flips high to low and low to high 16 total times with 8 "periods"
                    if (Scl_Counter_Ready) begin
                        if (Scl_Out) begin
                            Scl_Out_Local <= 0;
                            Scl_Counter <= 0;
                            Scl_Transmit_Counter <= Scl_Transmit_Counter + 1;
                        end
                        else begin
                            Scl_Out_Local <= 1;
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
                Sda_Edge_Checker <= Sda_In;
                
                if (Master_State_Out == Master_End) begin //double check that master module can go to end on its own/has the right conditions to go to end state
                    Scl_State <= Scl_Stop;
                end
                
                if (Master_State_Out == Master_Start) begin
                    Scl_Out_Local <= 1;
                    Scl_State <= Scl_Start;
                end
                //the below looks fine in the simulation but might have problems in some edge cases (breaks when first bit of the next transmission is 0)
                //fixed above test case by adding an OR to check if master is in receive  
                //look to change this to be dependent on a variable or on the state that the master module is in 

                else if (Sda_In || Master_State_Out == Master_Receive) begin //this code should not take priority over the stop state change
                    Scl_State <= Scl_Transmit;
                end
            end
            
            Scl_Stop: begin //011
                Scl_Out_Local <= 1;
                if (Sda_In) 
                    Scl_State <= Scl_Start;
            end

        endcase
    end
endmodule
module i2c_scl //enventually this will get combined with the master module 
    (input clk,
    inout Scl_Data,
    input Sda_Data

    );

    parameter Scl_Start = 3'b000;
    parameter Scl_Transmit = 3'b001;
    parameter Scl_Ack = 3'b010;
    parameter Scl_Stop = 3'b011;

    reg [2:0] Scl_State;
    reg [4:0] Scl_Counter;
    reg Scl_Data;
    reg Sda_Edge_Checker;
    reg [3:0] Scl_Transmit_Counter;

    initial begin
        Scl_Counter = 5'd0;
        Scl_Transmit_Counter = 4'd0;
    end

    always @(posedge clk) begin
        case (Scl_State)
            Scl_Start: begin
                Scl_Counter <= Scl_Counter + 1'b1;
                if (Sda_Data == 1'b0) begin
                    Scl_Data <= 1'b0;
                    if (Scl_Counter == 5'd20) begin
                        Scl_Data <= 1'bZ;
                        Scl_Counter <= 5'd0;
                        Scl_State <= Scl_Transmit;
                    end
                end   
            end

            Scl_Transmit: begin
                if (Scl_Transmit_Counter < 4'd15) begin //the scl flips high to low and low to high 16 total times with 8 "periods"
                    Scl_Transmit_Counter <= Scl_Transmit_Counter + 4'd1;
                    if (Scl_Counter == 5'd20) begin
                        if (Scl_Data == 1'b1) begin
                            Scl_Data <= 1'b0;
                            Scl_Counter  <= 5'd0;
                        end
                        else begin
                            Scl_Data <= 1'bZ;
                            Scl_Counter <= 5'd0;
                        end
                    end
                    else begin
                        Scl_Counter <= Scl_Counter + 1'b1;
                    end
                end

                else begin
                    Scl_State <= Scl_Ack;
                    Scl_Transmit_Counter <= 4'd0; 
                end
            end
            
            Scl_Ack: begin //this is the state after the ack pulse where the SCL line is held low until the SDA line goes back low
                Sda_Edge_Checker <= Master_Data;
                
                if (Master_State == Master_End) begin //double check that master module can go to end on its own/has the right conditions to go to end state
                    Scl_State <= Scl_Stop;
                end

                else if (Sda_Edge_Checker && ~Master_Data) begin //this code should not take priority over the stop state change
                    Scl_State <= Scl_Transmit;
                end
            end

            Scl_Stop: begin
                Scl_Data <= 1'bZ;
                if (Sda_Data == 1'b1) 
                    Scl_State <= Scl_Start;
            end

        endcase
    end
endmodule
module i2c_scl 
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

    initial begin
        Scl_Counter = 5'd0;
    end

    always @(posedge clk) begin
        case (Scl_State)
            Scl_Start: begin
                Scl_Counter <= Scl_Counter + 1'b1;
                if (Sda_Data == 1'b0) begin
                    Scl_Data <= 0;
                    if (Scl_Counter == 5'd20) begin
                        Scl_Data <= 1'bZ;
                        Scl_Counter <= 5'b0;
                        Scl_State <= Scl_Transmit;
                    end
                end   
            end

            Scl_Transmit: begin
                
            end
            
            Scl_Ack: begin
                
            end

            Scl_Stop: begin
                Scl_Data <= 1'bZ;
                if (Sda_Data == 1'b1) 
                    Scl_State <= Scl_Start;
            end

        endcase
    end
endmodule
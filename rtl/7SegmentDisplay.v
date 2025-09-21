module segdisplay 
    (
        input clk,
        input [15:0] i_temp, i_rh,
        input i_r_temp, i_r_rh,
        output reg an7 = 1, an6 = 1, an5 = 1, an4 = 1, an3 = 1, an2 = 1, an1 = 1, an0 = 1, //common anode
        output reg ca = 1, cb = 1, cc = 1, cd = 1, ce = 1, cf = 1, cg = 1, dp = 1 //digit selector 
        //outputs are active low 
        
    );

    //table of temperatures decimal remainders that can be referenced 
    //ex 1255 % 10 = 5 

    genvar i;    
    generate
        wire [3:0] temp_lut [0:1389];

        for (i = 0; i < 1389; i = i + 1) begin
            assign temp_lut[i] = i % 10;
        end
    endgenerate

    //table of binary values that can be referenced
    parameter zero = 7'b0000001;
    parameter one = 7'b1001111;
    parameter two = 7'b0010010;
    parameter three = 7'b0000110;
    parameter four = 7'b1001100;
    parameter five = 7'b0100100;
    parameter six = 7'b0100000;
    parameter seven = 7'b0001111;
    parameter eight = 7'b0000000;
    parameter nine = 7'b0000100;
    parameter f_letter = 7'b0111000;
    parameter h_letter = 7'b1001000;
    
    wire [6:0] digit_lut [9:0];
    assign digit_lut[9] = nine;
    assign digit_lut[8] = eight;
    assign digit_lut[7] = seven;
    assign digit_lut[6] = six;
    assign digit_lut[5] = five;
    assign digit_lut[4] = four;
    assign digit_lut[3] = three;
    assign digit_lut[2] = two;
    assign digit_lut[1] = one;
    assign digit_lut[0] = zero;

    wire [3:0] temp_deci;
    wire [6:0] temp_int;

    wire [31:0] temp_temp;
    wire [31:0] temp_rh;

    wire [3:0] rh_deci;
    wire [6:0] rh_int;

    reg [3:0] out_digit = 1;
    
    reg [3:0] temp_bcd_shifts = 0;
    reg [14:0] double_dabble_temp;  
    reg [3:0] temp_tens;
    reg [3:0] temp_ones;

    reg [3:0] rh_bcd_shifts = 0;
    reg [14:0] double_dabble_rh;  
    reg [3:0] rh_tens;
    reg [3:0] rh_ones;

    reg [20:0] counter = 0;

    reg dd_temp_flag = 0;
    reg dd_rh_flag = 0;
    
    reg i_r_temp_flag = 0;
    reg i_r_rh_flag = 0;

    reg digit_out_flag = 0;

    //calculations according to the SHT40 datasheet
    assign temp_rh = (i_rh * 1250) >> 16; //get value for decimal LUT
    assign rh_deci = temp_lut[temp_rh]; //use the LUT to store the decimal digit
    assign rh_int = ((i_rh * 125) >> 16) - 6; //integer rh value

    assign temp_temp = (i_temp * 3150) >> 16; 
    assign temp_deci = temp_lut[temp_temp]; 
    assign temp_int = ((i_temp * 315) >> 16) - 49; // integer temperature value in F

    //double dabble algorithm for temperature to convert binary integer to BCD
    always @(posedge clk) begin
        if (i_r_temp && ~i_r_temp_flag) begin //code only runs once per temp/rh ready cycle
            if (dd_temp_flag == 0) begin
                double_dabble_temp [6:0] <= temp_int;
                double_dabble_temp [14:7] <= 0;
                dd_temp_flag <= 1;
            end

            if (temp_bcd_shifts < 7 && dd_temp_flag == 1) begin
                temp_bcd_shifts <= temp_bcd_shifts + 1;
                double_dabble_temp <= {double_dabble_temp[13:0], 1'b0};

                if (double_dabble_temp[9:6] > 4 && temp_bcd_shifts !== 6) begin //note that on the last operation there is no addition after the shift 
                    double_dabble_temp[10:7] <= double_dabble_temp[9:6] + 3;
                end               
            end

            if (temp_bcd_shifts == 7) begin 
                temp_bcd_shifts <= 0;
                dd_temp_flag <= 0;
                temp_tens <= double_dabble_temp [14:11];
                temp_ones <= double_dabble_temp [10:7];

                i_r_temp_flag <= 1;
            end
        end

        if (~i_r_temp)
            i_r_temp_flag <= 0;

    end

    //double dabble algorithm for RH to convert binary integer to BCD
    always @(posedge clk) begin
        if (i_r_rh && ~i_r_rh_flag) begin //code only runs once per temp/rh ready cycle
            if (dd_rh_flag == 0) begin
                double_dabble_rh [6:0] <= rh_int;
                double_dabble_rh [14:7] <= 0;
                dd_rh_flag <= 1;
            end

            if (rh_bcd_shifts < 7 && dd_rh_flag == 1) begin 
                rh_bcd_shifts <= rh_bcd_shifts + 1;
                double_dabble_rh <= {double_dabble_rh[13:0], 1'b0};

                if (double_dabble_rh[9:6] > 4 && rh_bcd_shifts !== 6) begin //note that on the last operation there is no addition after the shift 
                    double_dabble_rh[10:7] <= double_dabble_rh[9:6] + 3;
                end               
            end

            if (rh_bcd_shifts == 7) begin 
                rh_bcd_shifts <= 0;
                dd_rh_flag <= 0;
                rh_tens <= double_dabble_rh [14:11];
                rh_ones <= double_dabble_rh [10:7];

                i_r_rh_flag <= 1;
            end
        end

        if (~i_r_rh)
            i_r_rh_flag <= 0;

    end

    //the counter value was picked so that the decimal place value can sort of be seen but not too slow that the display flickers
    //assigns from leftmost display to rightmost and loops
    
    always @(posedge clk) begin
        case (out_digit) //some kind of counter so that it doesnt immediately move to the next state
            1: begin
                if (~digit_out_flag) begin
                    {an7, an6, an5, an4, an3, an2, an1, an0} <= 8'b01111111;
                    {ca, cb, cc, cd, ce, cf, cg} <= digit_lut[temp_tens];
                    dp <= 1;
                    digit_out_flag <= 1;
                end

                counter <= counter + 1;
                if (counter > 288000) begin
                    digit_out_flag <= 0;
                    counter <= 0;
                    out_digit <= 2;
                end
            end
            2: begin
                if (~digit_out_flag) begin
                    {an7, an6, an5, an4, an3, an2, an1, an0} <= 8'b10111111;
                    {ca, cb, cc, cd, ce, cf, cg} <= digit_lut[temp_ones];
                    dp <= 0;
                    digit_out_flag <= 1;
                end

                counter <= counter + 1;
                if (counter > 288000) begin
                    digit_out_flag <= 0;
                    counter <= 0;
                    out_digit <= 3;
                end
            end
            3: begin
                if (~digit_out_flag) begin
                    {an7, an6, an5, an4, an3, an2, an1, an0} <= 8'b11011111;
                    {ca, cb, cc, cd, ce, cf, cg} <= digit_lut[temp_deci];
                    dp <= 1;
                    digit_out_flag <= 1;      
                end 

                counter <= counter + 1;
                if (counter > 288000) begin
                    digit_out_flag <= 0;
                    counter <= 0;
                    out_digit <= 4;
                end         
            end
            4: begin  
                if (~digit_out_flag) begin              
                    {an7, an6, an5, an4, an3, an2, an1, an0} <= 8'b11101111;
                    {ca, cb, cc, cd, ce, cf, cg} <= f_letter;
                    dp <= 1;
                    digit_out_flag <= 1;
                end

                counter <= counter + 1;
                if (counter > 288000) begin
                    digit_out_flag <= 0;
                    counter <= 0;
                    out_digit <= 5;
                end
            end
            5: begin
                if (~digit_out_flag) begin
                    {an7, an6, an5, an4, an3, an2, an1, an0} <= 8'b11110111;
                    {ca, cb, cc, cd, ce, cf, cg} <= digit_lut[rh_tens];
                    dp <= 1;
                    digit_out_flag <= 1;
                end

                counter <= counter + 1;
                if (counter > 288000) begin
                    digit_out_flag <= 0;
                    counter <= 0;
                    out_digit <= 6;
                end
            end
            6: begin
                if (~digit_out_flag) begin
                    {an7, an6, an5, an4, an3, an2, an1, an0} <= 8'b11111011;
                    {ca, cb, cc, cd, ce, cf, cg} <= digit_lut[rh_ones];
                    dp <= 0;
                    digit_out_flag <= 1;
                end

                counter <= counter + 1;
                if (counter > 288000) begin
                    digit_out_flag <= 0;
                    counter <= 0;
                    out_digit <= 7;
                end
            end
            7: begin
                if (~digit_out_flag) begin
                    {an7, an6, an5, an4, an3, an2, an1, an0} <= 8'b11111101;
                    {ca, cb, cc, cd, ce, cf, cg} <= digit_lut[rh_deci];
                    dp <= 1;
                    digit_out_flag <= 1;
                end

                counter <= counter + 1;
                if (counter > 288000) begin
                    digit_out_flag <= 0;
                    counter <= 0;
                    out_digit <= 8;
                end
            end
            8: begin
                if (~digit_out_flag) begin
                    {an7, an6, an5, an4, an3, an2, an1, an0} <= 8'b11111110;
                    {ca, cb, cc, cd, ce, cf, cg} <= h_letter;
                    dp <= 1;
                    digit_out_flag <= 1;
                end

                counter <= counter + 1;
                if (counter > 288000) begin
                    digit_out_flag <= 0;
                    counter <= 0;
                    out_digit <= 1;
                end
            end

        endcase
    end
endmodule

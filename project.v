module project
    (
    CLOCK_50,
    // Your inputs and outputs here
    KEY, SW, HEX0, HEX6, HEX7, LEDR, LEDG, HEX4, HEX5,
    // The ports below are for the VGA output.  Do not change.
    VGA_CLK,    //  VGA Clock
    VGA_HS,     //  VGA H_SYNC
    VGA_VS,     //  VGA V_SYNC
    VGA_BLANK_N,    //  VGA BLANK
    VGA_SYNC_N, //  VGA SYNC
    VGA_R,      //  VGA Red[9:0]
    VGA_G,      //  VGA Green[9:0]
    VGA_B       //  VGA Blue[9:0]
    );

    input CLOCK_50;
    input [17:0] SW; // SW1, SW0 are switches for the mux/ratedivider
    input [3:0] KEY; // KEY[3:1] are the controls for the game, KEY[0] is reset
    output [17:0] LEDR;
    output [6:0] HEX0, HEX6, HEX7, HEX4, HEX5;
    output [7:0] LEDG;

    // Declare your inputs and outputs here
    // Do not change the following outputs
    output    VGA_CLK;              //  VGA Clock
    output    VGA_HS;               //  VGA H_SYNC
    output    VGA_VS;               //  VGA V_SYNC
    output    VGA_BLANK_N;          //  VGA BLANK
    output    VGA_SYNC_N;           //  VGA SYNC
    output    [9:0]    VGA_R;           //  VGA Red[9:0]
    output    [9:0]    VGA_G;           //  VGA Green[9:0]
    output    [9:0]    VGA_B;           //  VGA Blue[9:0]
    
    wire resetn;
    assign resetn = KEY[0];
    
    // Create the colour, x, y and writeEn wires that are inputs to the controller.
    wire [2:0] colour;
    wire [7:0] x;
    wire [6:0] y;
    wire writeEn;

    // Create an Instance of a VGA controller - there can be only one!
    // Define the number of colours as well as the initial background
    // image file (.MIF) for the controller.
    vga_adapter VGA(
            .resetn(resetn),
            .clock(CLOCK_50),
            .colour(colour),
            .x(x),
            .y(y),
            .plot(writeEn),
            /* Signals for the DAC to drive the monitor. */
            .VGA_R(VGA_R),
            .VGA_G(VGA_G),
            .VGA_B(VGA_B),
            .VGA_HS(VGA_HS),
            .VGA_VS(VGA_VS),
            .VGA_BLANK(VGA_BLANK_N),
            .VGA_SYNC(VGA_SYNC_N),
            .VGA_CLK(VGA_CLK));
        defparam VGA.RESOLUTION = "160x120";
        defparam VGA.MONOCHROME = "FALSE";
        defparam VGA.BITS_PER_COLOUR_CHANNEL = 1;
        defparam VGA.BACKGROUND_IMAGE = "black.mif";
            
    // Put your code here. Your code should produce signals x,y,colour and writeEn/plot
    // for the VGA controller, in addition to any other functionality your design may require.

    wire [24:0] load_val;
    wire [2:0] switch; // switch to control the speed of the game
    mux8to1 m0(.SWITCH(switch), .OUT(load_val));

    wire enable_sig;
    ratedivider r0(.clock(CLOCK_50), .load_val(load_val), .enable(enable_sig));

    wire [143:0] alt_col;
    assign alt_col = 144'b100010001010100100001100100001010001100010100001100001010100001100010010100010001010100001010001100100100001001100001010100010001100010100001010;
     
    control c0(
        .clock(CLOCK_50), .reset(resetn), 
        .x_coord(x), .y_coord(y), .colour(colour),
        .draw(writeEn), .HEX0(HEX0), 
        .enable(enable_sig), .alt_col(alt_col), .switch(switch), .start(SW[17]),
        .lives(output_lives), .lives2(output_lives2), .second_player(second_player)
        );

    wire second_player;
    assign second_player = SW[16];
	 
	 // 1st player
    
    wire [6:0] score;
	 
    wire [3:0] num_lives;
	 assign num_lives = 4'd8;
	 
    wire [3:0] output_lives;

    datapath d0(.num_lives(num_lives), .clock(enable_sig), .keys(SW[2:0]),
        .x(x), .y(y), .colour(colour), .score(score), .output_lives(output_lives),
        .second_player(1'b1));

    score_display s0(.IN(score), .OUT1(HEX5), .OUT0(HEX4));
     
    display_lives dl0(.LIVES(output_lives), .LED(LEDG[7:0]));

    // 2nd player
    wire [3:0] num_lives2;
	 assign num_lives2 = 4'd8;

    wire [6:0] score2;
    wire [3:0] output_lives2;

    datapath d1(.num_lives(num_lives2), .clock(enable_sig), .keys(SW[10:8]),
	     .x(x), .y(y), .colour(colour), .score(score2),
        .output_lives(output_lives2), .second_player(second_player));

    display_lives dl1(.LIVES(output_lives2), .LED(LEDR[17:10]));

    score_display s1(.IN(score2), .OUT1(HEX7), .OUT0(HEX6));
endmodule

module control(clock, reset, enable, x_coord, y_coord, colour, draw, alt_col, switch,
    start, lives, lives2, second_player, HEX0);
    input clock;
    input reset;
    input enable;
    input start;
    input [143:0] alt_col;
	 input [3:0] lives;
    input [3:0] lives2;
    input second_player;
	 output [6:0] HEX0;
    output reg [7:0] x_coord;
    output reg [6:0] y_coord;
    output reg [2:0] colour; // goes into the vga adapter
    output reg draw;

    output reg [2:0] switch;
     
    reg [3:0] current_state, next_state; 
    localparam  Load = 4'd0, Vertical = 4'd1, RESET_VAL = 4'd2, DRAW_PIXEL = 4'd3, FINISH = 4'd4, END = 4'd5,
        RESET_Y = 4'd6, START = 4'd7;

    // data of the moving pixel
    reg [7:0] x_dot;
    reg [6:0] y_dot;
    reg drawn;

    // boolean values to check if an operation was performed successfully
    reg reseted_y;
    reg finished;
    reg transition1;
    reg transition2;
    reg loaded;
     
    hex_display h0(.IN(current_state), .OUT(HEX0[6:0]));

    // Next state logic aka our state table
    always@(posedge clock)
    begin: state_table 
        case (current_state)

            Load:
                begin
                    if (loaded == 1'b1)
                        next_state = Vertical;
                    else
                        next_state = Load;
                end

            Vertical:
                begin
                    if (x_coord >= 8'b10001000) // x exceeds 136 (last vertical bar is drawn)
                        next_state = RESET_VAL;
                    else if (y_coord >= 7'b1111000) // y exceeds 120 (all pixels are drawn)
                        next_state = RESET_Y; // go to transition state to reset the value of y and increment x by 25
                    else 
                        next_state = Vertical;
                end

            RESET_Y:
                begin
                    if (transition1 == 1'b1) // if a reset actually happenedmodule project
                        next_state = Vertical; // go back to vertical to keep drawing the vertical line
                    else
                        next_state = RESET_Y; // stay in here until a reset happens
                end

            RESET_VAL: 
                begin 
                    if (reseted_y == 1'b1)
                        next_state = START;
                    else
                        next_state = RESET_VAL;
                end

            START:
                begin
                    if (start == 1'b1)
                        next_state = DRAW_PIXEL;
                    else
                        next_state = START;
                end

            DRAW_PIXEL: 
                begin

                    if (second_player && (lives >= 4'b1000 || lives2 >= 4'b1000)) // 2 player, first to lose all end game
                        next_state = END;
								
						  else if (lives >= 4'b1000) // 1 player, and lost
                        next_state = END;
                    else if (x_coord >= 8'b10100000) // 160, increment y
                       next_state = FINISH;
                    else
                       next_state = DRAW_PIXEL; // keep incrememting x
                end
           
            FINISH:
                begin
                    if (y_coord >= 7'b1100000)
                        next_state = END; // end the game
                    else if (finished == 1'b1)
                        next_state = DRAW_PIXEL; // reset the x value and increment y
                    else
                        next_state = FINISH;
                end
                      
            END: next_state = END; // can make a loading page later let the user push a button to start the game

            default: next_state = END;
        endcase
    end // state_table

    wire [2:0] color_shift;
    assign colour_shift = 3'b001; // start at blue

    wire [7:0] start_x;
    assign start_x = 8'b00001010;

    reg [143:0] game_col;
    // Output logic aka all of our datapath control signals
    always @(posedge clock)
        begin: enable_signals
            case (current_state) 

                Load:
                    begin
						      x_coord <= 8'b00001111; // start the first vertical bar at x = 10
						      colour <= 3'b110;
						      game_col <= alt_col;
						      draw <= 1'b1;
						     transition1 <= 1'b1;
						  if (start == 1'b1)
                        loaded <= 1'b1;
                    end

                Vertical:
                     begin
                        y_coord <= y_coord + 7'b0000001;
                        draw <= 1'b1;
                        transition1 <= 1'b0;
                    end

                RESET_Y:
                    begin
                        x_coord <= x_coord + 8'b00001010; // increment by 25 pixels (00011001)
                        y_coord <= 7'b0;
						      draw <= 1'b0;
                        transition1 <= 1'b1;
                    end

                RESET_VAL: // move the coordinate back to the top left
                    begin
                        x_coord <= 8'b0;
                        y_coord <= 7'b0000110;
                        colour <= 3'b100;
                        reseted_y <= 1'b1;
                    end

                DRAW_PIXEL:
                    begin
                        if (enable == 1'b1)
                            begin
                                draw <= 1'b1;
                                if ((x_coord - 15) % 30 == 0) // x val is in the set {10, 35, 60, 85, 110, 135}
                                    begin // change colours right after the red vertical bar
                                        colour <= game_col[143:141];
                                        game_col <= game_col << 3;
                                    end
                                x_coord <= x_coord + 8'b00000001; // move x coordinate one spot to the right
                            end
								finished <= 1'b0;
                    end

                FINISH:
                    begin
                        switch <= switch + 1;
                        y_coord <= y_coord + 7'b0000110; // move y coordinate 6 spots down
                        x_coord <= 8'b0; // reset x value
                        draw <= 1'b0;
                        finished <= 1'b1;
                    end
            endcase
        end // enable_signals

    // current_state registers
    always@(posedge clock)
        begin: state_FFs
            if(~reset)
                current_state <= END; // reset the state back to load x
            else
                current_state <= next_state; // move to the next state
        end // state_FFS
endmodule

module hex_display(IN, OUT);
    input [3:0] IN;
    output reg [6:0] OUT;
    
    always @(*)
        begin
            case(IN[3:0])
                4'b0000: OUT = 7'b1000000;
                4'b0001: OUT = 7'b1111001;
                4'b0010: OUT = 7'b0100100;
                4'b0011: OUT = 7'b0110000;
                4'b0100: OUT = 7'b0011001;
                4'b0101: OUT = 7'b0010010;
                4'b0110: OUT = 7'b0000010;
                4'b0111: OUT = 7'b1111000;
                4'b1000: OUT = 7'b0000000;
                4'b1001: OUT = 7'b0011000;
                4'b1010: OUT = 7'b0001000;
                4'b1011: OUT = 7'b0000011;
                4'b1100: OUT = 7'b1000110;
                4'b1101: OUT = 7'b0100001;
                4'b1110: OUT = 7'b0000110;
                4'b1111: OUT = 7'b0001110;
        
                default: OUT = 7'b0111111;
            endcase
        end
endmodule

module mux8to1(SWITCH, OUT, HEX);
    input [2:0] SWITCH;
    output reg [24:0] OUT;
    output [6:0] HEX;
	 
    always @(*)
    begin
        case (SWITCH[2:0])	
				3'b111: OUT = 25'b0000100000000101100111111;
				3'b100: OUT = 25'b0000111000101111000000000;
            3'b001: OUT = 25'b0001000110101111000000000; 			
            3'b110: OUT = 25'b0001100000100000000000000;
            3'b011: OUT = 25'b0001100000001111000001111; 
            3'b000: OUT = 25'b0010000000000000000000000; 
        endcase
    end 
    hex_display h0(.IN(4'b0000 + SWITCH[2:0]), .OUT(HEX[6:0]));
endmodule

module ratedivider(clock, load_val, enable);
    input clock;
    input [24:0] load_val;
    output reg enable;
    reg [24:0] counter;

    always @(posedge clock)
        begin
            if (counter == load_val)
                begin
                    enable <= 1'b1;
                    counter <= 25'b0000000000000000000000000;
                end 
            else
                begin
                    counter <= counter + 25'b0000000000000000000000001;
                    enable <= 1'b0;
                end
        end
endmodule

module score_display(IN, OUT1, OUT0);
    input [6:0] IN; // highest score is 9L6 [7 bits]
    output [6:0] OUT1;
    output [6:0] OUT0;
    
    reg [3:0] first_digit;
    reg [4:0] second_digit;

    always @(*)
        begin
            second_digit = IN % 5'b01010;
            if (IN <= 5'b01001)
                first_digit <= 4'b0000;
            else if (IN <= 7'b0010011)
                first_digit <= 4'b0001;
            else if (IN <= 7'b0011101)
                first_digit <= 4'b0010;
            else if (IN <= 7'b0100111)
                first_digit <= 4'b0011;
            else if (IN <= 7'b0110001)
                first_digit <= 4'b0100;
            else if (IN <= 7'b0111011)
                first_digit <= 4'b0101;
            else if (IN <= 7'b1000101)
                first_digit <= 4'b0110;
            else if (IN <= 7'b1001111)
                first_digit <= 4'b0111;
            else if (IN <= 7'b1011001)
                first_digit <= 4'b1000;
            else if (IN <= 7'b1100011)
                first_digit <= 4'b1001;
        end
    
    hex_display h1(first_digit, OUT1);
    hex_display h0(second_digit [3:0], OUT0);
endmodule

module datapath(num_lives, clock, keys, x, y, colour, score, output_lives, second_player);
    input clock; // try 50_MHz clock or rate divider enable signal
    input [2:0] keys;
    input [7:0] x;
    input [6:0] y;
    input [2:0] colour;
	 input [3:0] num_lives;
    input second_player;
     
    output reg [6:0] score;
	output reg [3:0] output_lives;
	 
    always @(posedge clock)
        begin	 
            if (((x - 4'd15) % 5'd30) == 0) // x val is in the set {10, 35, 60, 85, 110, 135}
                begin
                    if (~keys == 3'b000)  // user enters nothing -> deduct 1 point only if score is not 0
                        begin
                            output_lives <= output_lives + 4'b0001; // example : 111111 on LEDR -> 011111 on LEDR after losing a life
                        if (score != 5'b00000)
								    score <= score - 5'b00001;
						      end
                    else if (~keys == colour) // user enters the correct input -> add 2 points only if score not 30+
                        score <= score + 5'b00010;
                    else // only subtract 2 if the score is at least 2
                        begin
							       if (score >= 5'b00010)
                                score <= score - 5'b00010; // user enters the incorrect input -> deduct 2 point
							       else if (score == 5'b00001)
								        score <= score - 5'b00001;
                            output_lives <= output_lives + 4'b0001;
                        end
					     if (output_lives == 4'd9)
						      output_lives <= 4'd8;
                end

            if (second_player == 1'b0)
                begin
                    score <= 7'b0000000;
                    output_lives <= 4'd9;
                end
        end
endmodule

module display_lives (LIVES, LED);
    input [3:0] LIVES;
    output reg [7:0] LED;
     
    always @(*)
    begin
        case (LIVES[3:0])
            4'b1010: LED = 8'b11111111; 
            4'b1001: LED = 8'b11111111; 
            4'b1000: LED = 8'b11111111; 
            4'b0111: LED = 8'b11111110;  
            4'b0110: LED = 8'b11111100; 
            4'b0101: LED = 8'b11111000;  
            4'b0100: LED = 8'b11110000;  
            4'b0011: LED = 8'b11100000; 
            4'b0010: LED = 8'b11000000; 
            4'b0001: LED = 8'b10000000; 
            4'b0000: LED = 8'b00000000; 
            default: LED = 8'b11111111;
        endcase
        LED = ~LED;
    end 
endmodule

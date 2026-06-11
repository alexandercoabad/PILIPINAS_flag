/*
 * SPDX-License-Identifier: Apache-2.0
 * SPDX-FileCopyrightText: 2026 Uri Shaked
 * Fixed Waving Outer Edges via Transparency Masking
 */

`default_nettype none

parameter LOGO_WIDTH = 128;   
parameter LOGO_HEIGHT = 64;   
parameter DISPLAY_WIDTH = 640;  
parameter DISPLAY_HEIGHT = 480;  

module tt_um_tinytapeout_dvd_screensaver (
    input  wire [7:0] ui_in,    
    output wire [7:0] uo_out,   
    input  wire [7:0] uio_in,   
    output wire [7:0] uio_out,  
    output wire [7:0] uio_oe,   
    input  wire       ena,      
    input  wire       clk,      
    input  wire       rst_n     
);


  // VGA signals
  wire hsync;
  wire vsync;
  wire video_active;
  wire [9:0] pix_x;
  wire [9:0] pix_y;
  
  wire [9:0] x = pix_x - logo_left;
  wire [9:0] y = pix_y - logo_top;

  // Reverted to a perfect, predictable flat bounding box region
  wire logo_region = (pix_x >= logo_left && pix_x < logo_left + LOGO_WIDTH) &&
                     (pix_y >= logo_top  && pix_y < logo_top + LOGO_HEIGHT);

  // --- WAVE ENGINE ---
  reg [5:0] wave_timer;      
  wire [5:0] wave_index;     
  reg signed [3:0] sine_offset; 

  assign wave_index = x[5:0] + wave_timer;

  // Tiny 8-step hardware sine approximation LUT
  always @(*) begin
    case (wave_index[5:3]) 
      3'b000: sine_offset =  4'sb0000; //  0
      3'b001: sine_offset =  4'sb0010; //  2
      3'b010: sine_offset =  4'sb0100; //  4
      3'b011: sine_offset =  4'sb0010; //  2
      3'b100: sine_offset =  4'sb0000; //  0
      3'b101: sine_offset = -4'sb0010; // -2
      3'b110: sine_offset = -4'sb0100; // -4
      3'b111: sine_offset = -4'sb0010; // -2
    endcase
  end

  // Calculate the wave position
  wire signed [10:0] full_y_calc = $signed({1'b0, y[5:0]}) + sine_offset;
  
  // Track if the wave calculation naturally escapes our 0-63 canvas height
  wire out_of_bounds = (full_y_calc < 0) || (full_y_calc > 63);

  wire [1:0] pixel_color;

  // Feed the ROM directly with the raw calculation bits
  bitmap_rom rom1 (
      .x(x[6:0]), 
      .y(full_y_calc[5:0]), 
      .pixel_color(pixel_color)
  );

  // Dynamic Color Generation Logic
  reg r_bit, g_bit, b_bit;

  always @(*) begin
    // If we are outside the logo region, or the wave calculation pushes the 
    // current pixel off the edge of the flag fabric, display transparent black background!
    if (!video_active || !logo_region || out_of_bounds) begin
      r_bit = 1'b0; g_bit = 1'b0; b_bit = 1'b0; 
    end else begin
      case (pixel_color)
        2'b01: begin // White Triangle Section
          r_bit = 1'b1; g_bit = 1'b1; b_bit = 1'b1;
        end
        2'b10: begin // Flag Body Section (Split between Blue & Red)
          if (full_y_calc[5:0] < 32) begin 
            r_bit = 1'b0; g_bit = 1'b0; b_bit = 1'b1; // Blue Top
          end else begin
            r_bit = 1'b1; g_bit = 1'b0; b_bit = 1'b0; // Red Bottom
          end
        end
        2'b11: begin // Golden Yellow Elements (Sun and 2 Stars)
          r_bit = 1'b1; g_bit = 1'b1; b_bit = 1'b0; 
        end
        default: begin // 2'b00 Safety Fallback
          r_bit = 1'b0; g_bit = 1'b0; b_bit = 1'b0;
        end
      endcase
    end
  end

  // Hardware PMOD pinout mapping
  assign uo_out = {
    hsync, 
    b_bit, 
    g_bit, 
    r_bit, 
    vsync, 
    b_bit, 
    g_bit, 
    r_bit  
  };

  assign uio_out = 8'b00000000;
  assign uio_oe  = 8'b00000000;
  wire _unused_ok = &{ena, ui_in, uio_in};

  reg [9:0] prev_y;
  vga_sync_generator vga_sync_gen (
      .clk(clk),
      .reset(~rst_n),
      .hsync(hsync),
      .vsync(vsync),
      .display_on(video_active),
      .hpos(pix_x),
      .vpos(pix_y)
  );

  reg [9:0] logo_left;
  reg [9:0] logo_top;
  reg dir_x;
  reg dir_y;

  always @(posedge clk) begin
    if (~rst_n) begin
      logo_left <= 200;
      logo_top <= 200;
      dir_y <= 0;
      dir_x <= 1;
      wave_timer <= 0;
    end else begin
      prev_y <= pix_y;
      if (pix_y == 0 && prev_y != pix_y) begin
        wave_timer <= wave_timer + 1; 

        logo_left <= logo_left + (dir_x ? 1 : -1);
        logo_top  <= logo_top + (dir_y ? 1 : -1);

        if (logo_left <= 1 && !dir_x) begin
          dir_x <= 1;
        end
        if (logo_left >= (DISPLAY_WIDTH - LOGO_WIDTH - 1) && dir_x) begin
          dir_x <= 0;
        end
        if (logo_top <= 1 && !dir_y) begin
          dir_y <= 1;
        end
        if (logo_top >= (DISPLAY_HEIGHT - LOGO_HEIGHT - 1) && dir_y) begin
          dir_y <= 0;
        end
      end
    end
  end

endmodule





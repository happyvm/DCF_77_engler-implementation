`timescale 1ns/1ps
module ml_decoder_controller_tb;
  logic clk=0,rst=1,frame_valid=0,candidate_cest,candidate_dst_announcement;
  logic candidate_leap_announcement,candidate_leap_second,publish_valid;
  logic [5:0] candidate_minute,candidate_day,minute,day; logic [4:0] candidate_hour,hour;
  logic [2:0] candidate_weekday,weekday; logic [3:0] candidate_month,month;
  logic [7:0] candidate_year,year; logic cest,dst_announcement,leap_announcement;
  logic signed [19:0] level_best_score=1000,level_second_score=700; logic [19:0] score_gap;
  logic [1:0] consistent_count;
  logic scan_start=0,history_read_valid=0,history_read_enable,scan_busy;
  logic [11:0] history_write_pointer=0,history_read_address;
  ml_decoder_controller #(.CONSISTENT_FRAMES(3)) dut(.*); always #5 clk=~clk;
  task frame(input integer yy,mo,dd,dw,hh,mm,input logic z,a1,a2,leap);
    begin candidate_year=yy;candidate_month=mo;candidate_day=dd;candidate_weekday=dw;
      candidate_hour=hh;candidate_minute=mm;candidate_cest=z;candidate_dst_announcement=a1;
      candidate_leap_announcement=a2;candidate_leap_second=leap;
      frame_valid=1;@(posedge clk);#1;frame_valid=0; end
  endtask
  initial begin
    repeat(2)@(posedge clk);rst=0;
    // 59->00, 23->00 and non-leap February end; third coherent frame publishes.
    frame(23,2,28,2,23,59,0,0,0,0); frame(23,3,1,3,0,0,0,0,0,0);
    frame(23,3,1,3,0,1,0,0,0,0); if(!publish_valid)$fatal(1,"continuity qualification");
    // Leap day and year rollover.
    frame(24,2,28,3,23,59,0,0,0,0); frame(24,2,29,4,0,0,0,0,0,0);
    frame(24,2,29,4,0,1,0,0,0,0);
    frame(24,12,31,2,23,59,0,0,0,0); frame(25,1,1,3,0,0,0,0,0,0);
    // Last Sunday spring jump, explicitly announced.
    frame(25,3,30,7,1,59,0,1,0,0); frame(25,3,30,7,3,0,1,1,0,0);
    // Last Sunday autumn repeats the 02:00 hour.
    frame(25,10,26,7,2,59,1,1,0,0); frame(25,10,26,7,2,0,0,1,0,0);
    // Leap second accepted only with A2; next timestamp is still xx:00.
    frame(25,6,30,1,23,59,1,0,1,1); frame(25,7,1,2,0,0,1,0,0,0);
    $display("ml_decoder_controller_tb: PASS");$finish;
  end
endmodule

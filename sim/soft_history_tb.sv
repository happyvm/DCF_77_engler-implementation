`timescale 1ns/1ps
module soft_history_tb;
  logic clk=0,rst=1,write_valid=0,sample_valid,read_enable=0,read_valid,history_full;
  logic signed [7:0] am_evidence,pm_evidence,read_am_evidence,read_pm_evidence;
  logic [3:0] quality,read_quality; logic [5:0] second_position,read_second_position;
  logic [2:0] write_pointer,read_address; logic read_sample_valid; integer i;
  soft_history #(.DEPTH(5),.EVIDENCE_BITS(8),.QUALITY_BITS(4),.ADDR_BITS(3),.WORD_BITS(27)) dut(.*);
  always #5 clk=~clk;
  initial begin
    repeat(2) @(posedge clk); rst<=0; sample_valid<=1;
    for(i=0;i<6;i=i+1) begin am_evidence<=i; pm_evidence<=-i; quality<=i; second_position<=i;
      write_valid<=1; @(posedge clk); end
    write_valid<=0; read_address<=0; read_enable<=1; @(posedge clk); #1; read_enable<=0;
    if(!history_full || write_pointer!=1 || !read_valid || read_am_evidence!=5 || read_second_position!=5)
      $fatal(1,"history wrap/read failed");
    $display("soft_history_tb: PASS"); $finish;
  end
endmodule

// Code your design here
// DESIGN DUT
module fifo (
    input  logic       clk,
    input  logic       rst,
    input  logic       wr,
    input  logic       rd,
    input  logic [7:0] data_in,
    output logic [7:0] data_out,
    output logic       empty,
    output logic       full);

    // Internal Memory & Pointers
    reg   [7:0] temp_mem [0:15];
    logic [4:0] rd_addr;
    logic [4:0] wr_addr;

    always@(posedge clk) 
	begin
        if (rst) 
		begin
            rd_addr  <= 5'd0;
            wr_addr  <= 5'd0;
            data_out <= 8'd0;
            for (int i = 0; i < 16; i++) 
			begin
                temp_mem[i] <= 8'd0;
            end
        end 
		else 
		begin
            // 1. Independent Write Logic
            if (wr && !full) 
			begin
                temp_mem[wr_addr[3:0]] <= data_in;
                wr_addr <= wr_addr + 1'b1;
            end

            // 2. Independent Read Logic (Runs concurrently with write!)
            if (rd && !empty) 
			begin
                data_out <= temp_mem[rd_addr[3:0]];
                rd_addr  <= rd_addr + 1'b1;
            end
        end
    end

    // Status Flags
    assign empty = (rd_addr == wr_addr);
    assign full  = (rd_addr[4] != wr_addr[4]) && (rd_addr[3:0] == wr_addr[3:0]);

endmodule


// Code your testbench here
// or browse Examples

// Code your testbench here
// or browse Examples

interface fifo_if(input bit clk);
  logic       rst;
  logic       wr;
  logic       rd;
  logic [7:0] data_in;
  logic [7:0] data_out;
  logic       empty;
  logic       full;
  
  clocking wr_drv @(posedge clk);
  default input #1 output #1;
  output wr;
  output rst;
  output data_in;
  input full;
  endclocking :wr_drv
  
  clocking rd_drv @(posedge clk);
  default input #1 output #1;
  output rd;
  input empty;
  endclocking :rd_drv
  
  clocking wr_mon @(posedge clk);
  default input #1 output #1;
  input wr;
  input rst;
  input data_in;
  endclocking :wr_mon
  
  clocking rd_mon @(posedge clk);
  default input #1 output #1;
  input rd;
  input data_out;
  endclocking :rd_mon
  
  modport WR_DRV (clocking wr_drv);
  modport RD_DRV (clocking rd_drv);
  modport WR_MON (clocking wr_mon);
  modport RD_MON (clocking rd_mon);
  
endinterface

//TRANSACTION CLASS

class transaction;
    rand bit rst;
    rand bit wr;
    rand bit rd;
    rand bit [7:0] data_in;
    logic    [7:0] data_out;
    logic empty;
    logic full;
	 
	static int trans_id; 
	static int read_trans;
	static int write_trans;
	static int read_write_trans;

	 
	constraint c1 { {wr,rd} != 2'b0;}
	constraint c2 {data_in inside {[6:100]};}
	constraint c3 {data_in dist { 7:=100,18:=86,[20:90]:=20,[91:100]:/100};}
    constraint no_rst { rst == 0; }
	 
	function void display(input string message);
	$display("============DATA FROM %s =============",message);
	$display("\t transaction number is %d",trans_id);
	$display("\t read trans is %d",read_trans);
    $display("\t write trans is %d",write_trans);
    $display("\t read_write trans is %d",read_write_trans);
	$display("\t Input data is %d",data_in);
	$display("\t Output data is %d",data_out);
	endfunction
	
	function void post_randomize();
	if((this.rd ==1)&&(this.wr==0))
		read_trans++;
	if((this.rd ==0)&&(this.wr==1))
		write_trans++;
	if((this.rd ==1)&&(this.wr==1))
		read_write_trans++;
	endfunction
	
  function bit compare(input transaction rcv, output string message);
	compare='0;
	begin
		
		if(this.data_out != rcv.data_out)
		begin
			message="data mismatch";
			return(0);
		end
			message="succesfully compared";
			return(1);
    end
	endfunction
		
endclass


//GENERATOR CLASS

class gen;
transaction gentrans;
mailbox #(transaction) gen2rd;
mailbox #(transaction) gen2wr;
event gen_done;
int no_trans;

function new(mailbox #(transaction) gen2rd,mailbox #(transaction) gen2wr);
this.gen2rd=gen2rd;
this.gen2wr=gen2wr;
endfunction

task start();
fork
begin
	for(int i=0;i<no_trans;i++)
	begin
        gentrans=new();
		assert(gentrans.randomize());
        gentrans.trans_id++;
		gentrans.display("GENERATOR");
		gen2rd.put(gentrans);
		gen2wr.put(gentrans);
	end
-> gen_done;
end
join_none
endtask
endclass

//WRITE DRIVER CLASS

class wr_driver;
mailbox #(transaction) gen2wr;
transaction data2duv;
virtual fifo_if.WR_DRV wr_drv_if;
function new(mailbox #(transaction) gen2wr,virtual fifo_if.WR_DRV wr_drv_if);
this.gen2wr=gen2wr;
this.wr_drv_if=wr_drv_if;
endfunction

task start();
fork
forever
begin
	gen2wr.get(data2duv);
	drive();
end
join_none
endtask

task drive();
while (wr_drv_if.wr_drv.full == 1'b1) 
begin
    @(wr_drv_if.wr_drv);
end

	@(wr_drv_if.wr_drv);
	wr_drv_if.wr_drv.wr      <= data2duv.wr;
	wr_drv_if.wr_drv.data_in <= data2duv.data_in;
	wr_drv_if.wr_drv.rst     <= data2duv.rst;
	@(wr_drv_if.wr_drv);
	data2duv.full            = wr_drv_if.wr_drv.full;
	wr_drv_if.wr_drv.wr <= 0;
	repeat(2)@(wr_drv_if.wr_drv);
	
endtask

endclass


//READ DRIVER

class rd_driver;
mailbox #(transaction) gen2rd;
transaction data2duv;
virtual fifo_if.RD_DRV rd_drv_if;
function new(mailbox #(transaction) gen2rd,virtual fifo_if.RD_DRV rd_drv_if);
this.gen2rd=gen2rd;
this.rd_drv_if=rd_drv_if;
endfunction

task start();
fork
forever
begin
	gen2rd.get(data2duv);
	drive();
end
join_none
endtask

task drive();
while (rd_drv_if.rd_drv.empty == 1'b1) 
begin
    @(rd_drv_if.rd_drv);
end

	@(rd_drv_if.rd_drv);
	rd_drv_if.rd_drv.rd      <= data2duv.rd;
	@(rd_drv_if.rd_drv);
	data2duv.empty            = rd_drv_if.rd_drv.empty;
	rd_drv_if.rd_drv.rd      <= 0;
	repeat(2)@(rd_drv_if.rd_drv);
	
endtask
endclass


//WRITE MONITOR CLASS

class wr_monitor;
mailbox #(transaction) wr2sb;
transaction data2sb;
virtual fifo_if.WR_MON wr_mon_if;

function new(virtual fifo_if.WR_MON wr_mon_if,mailbox #(transaction) wr2sb);
this.wr2sb=wr2sb;
this.wr_mon_if=wr_mon_if;
endfunction

task start();
fork
forever
begin
	data2sb=new();
	monitor();
end
join_none
endtask

task monitor();
	 @(wr_mon_if.wr_mon);
	if(wr_mon_if.wr_mon.wr==1)
    begin
		data2sb.rst	    = wr_mon_if.wr_mon.rst;
		data2sb.wr	        = wr_mon_if.wr_mon.wr;
		data2sb.data_in	= wr_mon_if.wr_mon.data_in;
        wr2sb.put(data2sb);
    end
endtask
endclass


//READ MONITOR CLASS

class rd_monitor;
mailbox #(transaction) rd2sb;
mailbox #(transaction) reference;
transaction data2sb;
transaction refdata;
virtual fifo_if.RD_MON rd_mon_if;

function new(virtual fifo_if.RD_MON rd_mon_if,mailbox #(transaction) rd2sb,mailbox #(transaction) reference);
this.rd_mon_if=rd_mon_if;
this.rd2sb=rd2sb;
this.reference=reference;
endfunction

task start();
fork
forever
begin
	data2sb=new();
	refdata=new();
	monitor();
end
join_none
endtask

task monitor();
    @(rd_mon_if.rd_mon);
    if (rd_mon_if.rd_mon.rd == 1'b1) begin
        @(rd_mon_if.rd_mon); // Wait for DUT data_out to be valid
        
        // Populate actual data
        data2sb.rd       = 1'b1;
        data2sb.data_out = rd_mon_if.rd_mon.data_out;
        rd2sb.put(data2sb);

        // Populate ref placeholder
        refdata.rd       = 1'b1;
        reference.put(refdata);
    end
endtask
endclass

//SCOREBOARD CLASS

class scoreboard;
transaction ref_data,t1,rcvd_data;
logic [7:0] refer [$];
event gen_done;
string diff;
event DONE;
int data_verified;
mailbox #(transaction) rd2sb;
mailbox #(transaction) wr2sb;
mailbox #(transaction) reference;
  
function new(mailbox #(transaction) rd2sb,mailbox #(transaction) wr2sb,mailbox #(transaction) reference,event gen_done);
this.rd2sb=rd2sb;
this.wr2sb=wr2sb;
this.reference=reference;
this.gen_done=gen_done;
cvg=new();
endfunction	

covergroup cvg;
 DATA : coverpoint t1.data_in {
		       bins seven={7};
			   bins low  = {[9:40]};
			   bins med  = {[45:80]};
			   bins high = {[81:99]};
							   }
WRITE : coverpoint t1.wr 	   {
			   bins high = {1};
							   }
DATA_X_WRITE : cross DATA,WRITE;
endgroup

	   
task check();
  fork
    // Write side collector + coverage
    forever 
      begin
      	wr2sb.get(t1);
      	cvg.sample();
      	if (t1.wr)
        refer.push_back(t1.data_in);
      end

    // Read side checker
    forever 
    begin
      rd2sb.get(ref_data);          // actual from DUT
      reference.get(rcvd_data);     // placeholder

      if (rcvd_data.rd && refer.size() > 0) begin
        rcvd_data.data_out = refer.pop_front();

        if (!ref_data.compare(rcvd_data, diff)) begin
          $display("ERROR: %s", diff);
        end 
        else 
        begin
          $display("PASS: data matched");
          data_verified++;
        end
      end
    end
  join_none
endtask

task start();
  check();   // just launches the two forever threads

  // Wait for all expected reads to be verified
  wait (gen_done.triggered);
  #300;
  -> DONE;
endtask

function void report();
$display("===============SCOREBOARD DATA==================");
$display("Current coverage = %f",cvg.get_coverage());
  $display("Current cross coverage = %0.2f",cvg.DATA_X_WRITE.get_coverage());
endfunction

endclass



//=====================ENV CLASS============================
class env;

virtual fifo_if.WR_DRV wr_drv;
virtual fifo_if.RD_DRV rd_drv;
virtual fifo_if.WR_MON wr_mon;
virtual fifo_if.RD_MON rd_mon;

function new (virtual fifo_if.WR_DRV wr_drv,virtual fifo_if.RD_DRV rd_drv,
			  virtual fifo_if.WR_MON wr_mon,virtual fifo_if.RD_MON rd_mon);
this.wr_drv=wr_drv;
this.rd_drv=rd_drv;
this.wr_mon=wr_mon;
this.rd_mon=rd_mon;
endfunction
mailbox #(transaction) gen2rd=new();
mailbox #(transaction) gen2wr=new();
mailbox #(transaction) rd2sb=new();
mailbox #(transaction) wr2sb=new();
mailbox #(transaction) reference=new();

gen genh;
wr_driver wr_drvh;
rd_driver rd_drvh;
wr_monitor wr_monh;
rd_monitor rd_monh;
scoreboard sbh;

task build();
genh=new(gen2rd,gen2wr);
wr_drvh=new(gen2wr,wr_drv);
rd_drvh=new(gen2rd,rd_drv);
wr_monh=new(wr_mon,wr2sb);
rd_monh=new(rd_mon,rd2sb,reference);
sbh=new(rd2sb,wr2sb,reference,genh.gen_done);
endtask: build

task start();
genh.start();
wr_drvh.start();
rd_drvh.start();
wr_monh.start();
rd_monh.start();
sbh.start();
endtask:start

task reset_dut();
    wr_drv.wr_drv.rst     <= 1'b1;  // Assert active-high reset
    wr_drv.wr_drv.wr      <= 1'b0;  // Disable write
    wr_drv.wr_drv.data_in <= 8'h00; // Clear input bus
    rd_drv.rd_drv.rd      <= 1'b0;  // Disable read
  repeat (2) @(wr_drv.wr_drv);

    wr_drv.wr_drv.rst     <= 1'b0;  // Deassert reset

    repeat (2) @(wr_drv.wr_drv);
endtask: reset_dut

task stop();
wait(sbh.DONE.triggered);
endtask:stop

task run();
reset_dut();
start();
stop();
sbh.report;
endtask :run

endclass



//=====================TEST CLASS==========================

class test;
env envh;
virtual fifo_if.WR_DRV wr_drv;
virtual fifo_if.RD_DRV rd_drv;
virtual fifo_if.WR_MON wr_mon;
virtual fifo_if.RD_MON rd_mon;

function new(virtual fifo_if.WR_DRV wr_drv,virtual fifo_if.RD_DRV rd_drv,
			 virtual fifo_if.WR_MON wr_mon,virtual fifo_if.RD_MON rd_mon);
this.wr_drv=wr_drv;
this.rd_drv=rd_drv;
this.wr_mon=wr_mon;
this.rd_mon=rd_mon;

envh=new(wr_drv,rd_drv,wr_mon,rd_mon);
endfunction

task build_and_run();
envh.build();
envh.genh.no_trans=16;
envh.run();
$finish;
endtask

endclass


/*********==========************=========    TOP MODULE   ==========************=========
`include wr_drv
`include rd_drv
`include wr_mon
`include rd_mon
`include scoreboard
`include ENV
`include TEST
*/

module top;
parameter cycle=10;
test testh;

reg clk=0;
fifo_if intf(clk);
fifo F1(.clk(clk),.rst(intf.rst),.wr(intf.wr),.rd(intf.rd),.data_in(intf.data_in),
        .data_out(intf.data_out),.empty(intf.empty),.full(intf.full));

initial 
begin
	testh=new(intf,intf,intf,intf);
	testh.build_and_run();
end

initial
begin
	forever #(cycle/2) clk=!clk;
 
end

initial
begin
	 $dumpfile("dump.vcd");
     $dumpvars(0, top);
end
endmodule
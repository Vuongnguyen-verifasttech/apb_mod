//==============================================================================
// File          : apb_monitor.sv
// Author        : [vnguyen]
// Company       : [Verifast]
// Project       : APB Verification Environment
// Description   : APB Monitor - Thu thập transaction từ bus, hỗ trợ Back-to-Back
// Version       : 1.3 (Updated for new FSM DUT)
// Date          : 03-Jun-2026
//==============================================================================

`ifndef APB_MONITOR_SV
`define APB_MONITOR_SV

class apb_monitor extends uvm_monitor;
    `uvm_component_utils(apb_monitor)

    // Virtual interface
    virtual apb_if.monitor vif;
    
    // Analysis port
    uvm_analysis_port #(apb_transaction) mon_ap;

    function new(string name = "apb_monitor", uvm_component parent = null); 
        super.new(name, parent);
    endfunction 

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon_ap = new("mon_ap", this);
        
        if(!uvm_config_db#(virtual apb_if.monitor)::get(this, "", "vif", vif)) begin
            `uvm_fatal("MON", "Could not get APB monitor interface from config_db!")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        wait(vif.presetn == 1);
        `uvm_info(get_type_name(), "Monitor started after reset", UVM_MEDIUM);
        
        forever begin
            collect_transaction();
        end
    endtask

    //==================================================================
// COLLECT TRANSACTION - ĐÃ TỐI ƯU CHO FSM MỚI
//==================================================================
virtual task collect_transaction();
    apb_transaction trans;
    int wait_cnt = 0;

    // ------ 1. DETECT SETUP PHASE ------
    do begin
        @(vif.mon_cb);
    end while (!(vif.mon_cb.psel && !vif.mon_cb.penable));

    trans = apb_transaction::type_id::create("trans");
    trans.paddr  = vif.mon_cb.paddr;
    trans.pwrite = vif.mon_cb.pwrite;
    if (trans.pwrite) 
        trans.pwdata = vif.mon_cb.pwdata;

    `uvm_info(get_type_name(), $sformatf("Detected Setup | ADDR=0x%8h WRITE=%b", 
              trans.paddr, trans.pwrite), UVM_HIGH);

    // ------ 2. ACCESS PHASE & COUNT WAIT STATES ------
    // Chờ vào pha ACCESS (penable = 1)
    do begin
        @(vif.mon_cb);
    end while (!vif.mon_cb.penable);

    // Đếm số chu kỳ pready = 0 (wait states)
    wait_cnt = 0;
    while (!vif.mon_cb.pready) begin
        wait_cnt++;
        @(vif.mon_cb);
    end

    trans.wait_cycles = wait_cnt;   // Sửa: không trừ 1 nữa

    // Lấy kết quả cuối cùng
    trans.prdata  = vif.mon_cb.prdata;
    trans.pslverr = vif.mon_cb.pslverr;

    `uvm_info(get_type_name(), 
        $sformatf("Collected | ADDR=0x%8h WRITE=%b WAIT=%0d RDATA=0x%8h SLVERR=%b", 
                  trans.paddr, trans.pwrite, trans.wait_cycles, 
                  trans.pwrite ? 32'hxxxxxxxx : trans.prdata, trans.pslverr), 
        UVM_MEDIUM);

    mon_ap.write(trans);

    // ------ 3. END TRANSACTION - Hỗ trợ Back-to-Back tốt hơn ------
    // Chỉ chờ 1 clock để sẵn sàng bắt transaction tiếp theo
    @(vif.mon_cb);

endtask

endclass 

`endif
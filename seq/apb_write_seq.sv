//==============================================================================
// File          : apb_write_seq.sv
// Version       : 1.1 (Fixed Randomization constraint)
//==============================================================================

`ifndef APB_WRITE_SEQ_SV
`define APB_WRITE_SEQ_SV

class apb_write_seq extends apb_base_seq;
    `uvm_object_utils(apb_write_seq)

    rand int num_tx = 128;

    function new(string name = "apb_write_seq");
        super.new(name);
    endfunction

    virtual task body();
        apb_transaction tr;
        `uvm_info(get_type_name(), "============================================================", UVM_NONE);
        `uvm_info(get_type_name(), "           START APB_05: WRITE  SEQUENCE", UVM_NONE);
        `uvm_info(get_type_name(), "============================================================", UVM_NONE);

        repeat(num_tx) begin 
            tr = apb_transaction::type_id::create("tr");
            start_item(tr);
            
            // 🔥 SỬA TẠI ĐÂY: Ghi dữ liệu thì pwrite phải bằng 1!
            if (!tr.randomize() with {pwrite == 1;}) begin
                `uvm_error(get_type_name(), "Randomize failed for WRITE transaction!");
            end
            
            tr.seq_name = "WRITE_SEQ";
            finish_item(tr);
            `uvm_info(get_type_name(), $sformatf("TASK WRITE: Sent Write: ADDR = 0x%8h, DATA = 0x%8h", tr.paddr, tr.pwdata), UVM_MEDIUM)
        end
        `uvm_info(get_type_name(), "============================================================", UVM_NONE);
        `uvm_info(get_type_name(), "           COMPLETE APB_05:WRITE SEQUENCE", UVM_NONE);
        `uvm_info(get_type_name(), "============================================================", UVM_NONE);
    endtask
endclass
`endif
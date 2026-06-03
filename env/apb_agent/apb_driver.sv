class apb_driver extends uvm_driver #(apb_transaction);
    `uvm_component_utils (apb_driver)
    
    virtual apb_if.driver vif;
    bit b2b_mode = 1; // Bật mặc định để test DUT mới

    function new(string name = "apb_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction 

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual apb_if.driver)::get(this,"","vif", vif)) begin
            `uvm_fatal("DRV", "Couldn't get APB interface")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        reset_bus();
        wait(vif.presetn === 1'b1);
        
        forever begin 
            seq_item_port.get_next_item(req);
            drive_transaction(req);
            seq_item_port.item_done();
        end
    endtask

    task reset_bus();
        vif.drv_cb.psel    <= 0; 
        vif.drv_cb.penable <= 0; 
        vif.drv_cb.paddr   <= 0;
        vif.drv_cb.pwdata  <= 0;
        vif.drv_cb.pwrite  <= 0;
    endtask 

    task drive_transaction(apb_transaction tr);
        // ====== 1. SETUP PHASE =============
        vif.drv_cb.psel    <= 1;
        vif.drv_cb.penable <= 0;
        vif.drv_cb.paddr   <= tr.paddr;
        vif.drv_cb.pwrite  <= tr.pwrite;
        if (tr.pwrite) vif.drv_cb.pwdata <= tr.pwdata;
        
        @(vif.drv_cb); // Chờ 1 clock hết Setup Phase

        // ======== 2. ACCESS PHASE =============
        vif.drv_cb.penable <= 1;
        
        // Chờ phản hồi pready từ DUT
        while (!vif.drv_cb.pready) begin
            @(vif.drv_cb);
        end

        // Lấy dữ liệu READ nếu có tại chu kỳ pready=1
        if (!tr.pwrite) tr.prdata = vif.drv_cb.prdata;
        tr.pslverr = vif.drv_cb.pslverr;

        // ======== 3. END TRANSACTION & B2B OPTIMIZATION =============
        if (b2b_mode) begin
            // Kiểm tra xem Sequencer có sẵn gói tiếp theo không
            apb_transaction next_tr;
            seq_item_port.try_next_item(next_tr);
            
            if (next_tr != null) begin
                // Nếu có gói gối đầu, nạp thẳng thông tin SETUP cho gói sau ngay tại đây!
                vif.drv_cb.psel    <= 1;
                vif.drv_cb.penable <= 0; // Hạ penable xuống để tạo cạnh lên cho chu kỳ sau
                vif.drv_cb.paddr   <= next_tr.paddr;
                vif.drv_cb.pwrite  <= next_tr.pwrite;
                if (next_tr.pwrite) vif.drv_cb.pwdata <= next_tr.pwdata;
                
                // Vì gói sau đã được nạp gối đầu thành công, kết thúc item cũ
                req = next_tr; 
                // Không gọi @(vif.drv_cb), để vòng lặp chính bên ngoài quay lại quản lý pha ACCESS tiếp theo
            end else begin
                // Nếu không còn gói nào, hạ bus về IDLE bình thường
                vif.drv_cb.psel    <= 0;
                vif.drv_cb.penable <= 0;
                @(vif.drv_cb);
            end
        end else begin
            vif.drv_cb.psel    <= 0;
            vif.drv_cb.penable <= 0;
            @(vif.drv_cb);
        end
    endtask
endclass
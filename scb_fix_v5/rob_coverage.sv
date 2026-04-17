// ==== FILE: rob_coverage.sv ====
// Coverage collector đầy đủ theo testplan v2.1 §8.1 + §8.2
// FSM state dùng hierarchical probe: tb_top.dut.rob_state
  class rob_coverage extends uvm_subscriber #(rob_transaction);
    `uvm_component_utils(rob_coverage)
    virtual rob_if.MON vif;

    // ── Sampled variables ──
    // §8.1 cg_dispatch_width
    int dispatch_width;
    // §8.1 cg_partial_stall
    bit partial_stall;
    // §8.1 cg_wb_port_usage (per port)
    bit wb_port_hit [NUM_WB_PORTS];
    // §8.1 cg_simultaneous_wb
    int sim_wb_count;
    // §8.1 cg_commit_width
    int commit_width;
    // §8.1 cg_rob_occupancy
    int rob_occ_pct;
    // §8.1 cg_rob_state — probe từ DUT hierarchy
    // Encoding: 0=s_reset, 1=s_normal, 2=s_rollback, 3=s_wait_till_empty
    int fsm_state;
    // §8.1 cg_exception_type
    // 0=none, 1=dispatch_xcpt, 2=lxcpt, 3=csr_replay
    int xcpt_type;
    // §8.1 cg_branch_outcome: 0=none, 1=correct_resolve, 2=mispredict
    int br_outcome;
    // §8.1 cg_pointer_wrap
    bit head_wrapped, tail_wrapped;
    // §8.1 cg_fence_dispatch
    bit fence_dispatched;
    // §8.1 cg_lsu_clr_bsy
    bit lsu_clr_active;
    // §8.1 cg_csr_stall
    bit csr_stall_active;
    // §8.1 cg_arch_valid_pattern (4-bit)
    bit [3:0] arch_valid_pattern;
    // §8.1 cg_flush_type: 0=none, khác=flush_typ value
    int flush_type;
    // Cross helpers
    bit has_xcpt, has_misp;
    bit commit_ready;  // entry at head ready nhưng chưa commit
    int fence_count_in_dispatch;
    int xcpt_bank; // bank nào có exception: -1=none, 0..3

    logic [6:0] prev_head, prev_tail;

    // ═══════════════════════════════════════════════════════════
    // §8.1 FUNCTIONAL COVERGROUPS
    // ═══════════════════════════════════════════════════════════

    // cg_dispatch_width: Số uop dispatch mỗi cycle (0–4)
    covergroup cg_dispatch_width;
      cp_width: coverpoint dispatch_width {
        bins w0 = {0}; bins w1 = {1}; bins w2 = {2};
        bins w3 = {3}; bins w4 = {4};
      }
    endgroup

    // cg_partial_stall: Có/không partial stall
    covergroup cg_partial_stall;
      cp_ps: coverpoint partial_stall {
        bins no_stall = {0}; bins stall = {1};
      }
    endgroup

    // cg_wb_port_usage: Từng port 0–9 đã dùng chưa
    covergroup cg_wb_port_usage;
      cp_p0: coverpoint wb_port_hit[0]; cp_p1: coverpoint wb_port_hit[1];
      cp_p2: coverpoint wb_port_hit[2]; cp_p3: coverpoint wb_port_hit[3];
      cp_p4: coverpoint wb_port_hit[4]; cp_p5: coverpoint wb_port_hit[5];
      cp_p6: coverpoint wb_port_hit[6]; cp_p7: coverpoint wb_port_hit[7];
      cp_p8: coverpoint wb_port_hit[8]; cp_p9: coverpoint wb_port_hit[9];
    endgroup

    // cg_simultaneous_wb: Số WB port active cùng cycle (0–10)
    covergroup cg_simultaneous_wb;
      cp_sim: coverpoint sim_wb_count {
        bins none = {0}; bins one = {1}; bins two = {2};
        bins three = {3}; bins four = {4}; bins five = {5};
        bins six = {6}; bins seven = {7}; bins eight = {8};
        bins nine = {9}; bins ten = {10};
      }
    endgroup

    // cg_commit_width: Số uop commit mỗi cycle (0–4)
    covergroup cg_commit_width;
      cp_cw: coverpoint commit_width {
        bins c0 = {0}; bins c1 = {1}; bins c2 = {2};
        bins c3 = {3}; bins c4 = {4};
      }
    endgroup

    // cg_rob_occupancy: Mức đầy ROB 6 khoảng
    covergroup cg_rob_occupancy;
      cp_occ: coverpoint rob_occ_pct {
        bins empty    = {0};
        bins low      = {[1:25]};
        bins mid_low  = {[26:50]};
        bins mid_high = {[51:75]};
        bins high     = {[76:99]};
        bins full     = {100};
      }
    endgroup

    // cg_rob_state: FSM state — probe qua hierarchy
    covergroup cg_rob_state;
      cp_state: coverpoint fsm_state {
        bins s_reset           = {0};
        bins s_normal          = {1};
        bins s_rollback        = {2};
        bins s_wait_till_empty = {3};
      }
    endgroup

    // cg_exception_type: Nguồn exception
    covergroup cg_exception_type;
      cp_xtype: coverpoint xcpt_type {
        bins none         = {0};
        bins dispatch_xcpt = {1};
        bins lxcpt        = {2};
        bins csr_replay   = {3};
      }
    endgroup

    // cg_branch_outcome: correct resolve vs mispredict
    covergroup cg_branch_outcome;
      cp_br: coverpoint br_outcome {
        bins none      = {0};
        bins correct   = {1};
        bins mispredict = {2};
      }
    endgroup

    // cg_pointer_wrap: Head/tail wrap events
    covergroup cg_pointer_wrap;
      cp_head_wrap: coverpoint head_wrapped { bins no = {0}; bins yes = {1}; }
      cp_tail_wrap: coverpoint tail_wrapped { bins no = {0}; bins yes = {1}; }
    endgroup

    // cg_fence_dispatch: Fence instruction dispatched
    covergroup cg_fence_dispatch;
      cp_fence: coverpoint fence_dispatched { bins no = {0}; bins yes = {1}; }
    endgroup

    // cg_lsu_clr_bsy: LSU clear busy path exercised
    covergroup cg_lsu_clr_bsy;
      cp_lsu: coverpoint lsu_clr_active { bins no = {0}; bins yes = {1}; }
    endgroup

    // cg_csr_stall: CSR stall asserted
    covergroup cg_csr_stall;
      cp_csr: coverpoint csr_stall_active { bins no = {0}; bins yes = {1}; }
    endgroup

    // cg_arch_valid_pattern: 16 patterns of commit_arch_valids (4-bit)
    covergroup cg_arch_valid_pattern;
      cp_avp: coverpoint arch_valid_pattern {
        bins all_arch   = {4'b1111};
        bins none_arch  = {4'b0000};
        bins alt_01     = {4'b0101};
        bins alt_10     = {4'b1010};
        bins others[]   = default;
      }
    endgroup

    // cg_flush_type: Loại flush
    covergroup cg_flush_type;
      cp_ftype: coverpoint flush_type {
        bins none            = {0};
        bins xcpt            = {1};  // flush_typ encoding cho exception
        bins flush_on_commit = {2};  // flush_typ encoding cho flush_on_commit
        bins mispredict      = {3};  // flush_typ encoding cho mispredict redirect
        bins other[]         = default;
      }
    endgroup

    // ═══════════════════════════════════════════════════════════
    // §8.2 CROSS COVERGROUPS
    // ═══════════════════════════════════════════════════════════

    // dispatch_width × rob_occupancy
    covergroup cg_x_dispatch_occ;
      cp_d: coverpoint dispatch_width { bins b[] = {[0:4]}; }
      cp_o: coverpoint rob_occ_pct {
        bins low = {[0:50]}; bins high = {[51:99]}; bins full = {100};
      }
      cx: cross cp_d, cp_o;
    endgroup

    // wb_count × commit_width
    covergroup cg_x_wb_commit;
      cp_w: coverpoint sim_wb_count {
        bins low = {[0:2]}; bins mid = {[3:5]}; bins high = {[6:10]};
      }
      cp_c: coverpoint commit_width { bins b[] = {[0:4]}; }
      cx: cross cp_w, cp_c;
    endgroup

    // rob_state × exception
    covergroup cg_x_state_xcpt;
      cp_st: coverpoint fsm_state {
        bins s_normal = {1}; bins s_rollback = {2}; bins s_wait = {3};
      }
      cp_x: coverpoint has_xcpt { bins no = {0}; bins yes = {1}; }
      cx: cross cp_st, cp_x;
    endgroup

    // rob_state × mispredict
    covergroup cg_x_state_misp;
      cp_st: coverpoint fsm_state {
        bins s_normal = {1}; bins s_rollback = {2}; bins s_wait = {3};
      }
      cp_m: coverpoint has_misp { bins no = {0}; bins yes = {1}; }
      cx: cross cp_st, cp_m;
    endgroup

    // csr_stall × commit_ready
    covergroup cg_x_csr_commit;
      cp_csr: coverpoint csr_stall_active { bins off = {0}; bins on = {1}; }
      cp_rdy: coverpoint commit_ready { bins no = {0}; bins yes = {1}; }
      cx: cross cp_csr, cp_rdy;
    endgroup

    // rob_state × fence_dispatch
    covergroup cg_x_state_fence;
      cp_st: coverpoint fsm_state {
        bins s_normal = {1}; bins s_wait = {3};
      }
      cp_f: coverpoint fence_dispatched { bins no = {0}; bins yes = {1}; }
      cx: cross cp_st, cp_f;
    endgroup

    // dispatch_width × fence_count
    covergroup cg_x_dispatch_fence;
      cp_dw: coverpoint dispatch_width { bins b[] = {[0:4]}; }
      cp_fc: coverpoint fence_count_in_dispatch {
        bins none = {0}; bins some = {[1:3]}; bins all = {4};
      }
      cx: cross cp_dw, cp_fc;
    endgroup

    // exception_type × exception_bank
    covergroup cg_x_xcpt_bank;
      cp_xt: coverpoint xcpt_type {
        bins dispatch_xcpt = {1}; bins lxcpt = {2};
      }
      cp_bk: coverpoint xcpt_bank {
        bins bank0 = {0}; bins bank1 = {1}; bins bank2 = {2}; bins bank3 = {3};
        bins none  = {-1};
      }
      cx: cross cp_xt, cp_bk;
    endgroup

    // rob_occupancy × mispredict
    covergroup cg_x_occ_misp;
      cp_o: coverpoint rob_occ_pct {
        bins low = {[0:25]}; bins mid = {[26:75]}; bins high = {[76:99]}; bins full = {100};
      }
      cp_m: coverpoint has_misp { bins no = {0}; bins yes = {1}; }
      cx: cross cp_o, cp_m;
    endgroup

    // ═══════════════════════════════════════════════════════════
    // Constructor + build
    // ═══════════════════════════════════════════════════════════
    function new(string name, uvm_component parent);
      super.new(name, parent);
      // §8.1 functional
      cg_dispatch_width   = new();
      cg_partial_stall    = new();
      cg_wb_port_usage    = new();
      cg_simultaneous_wb  = new();
      cg_commit_width     = new();
      cg_rob_occupancy    = new();
      cg_rob_state        = new();
      cg_exception_type   = new();
      cg_branch_outcome   = new();
      cg_pointer_wrap     = new();
      cg_fence_dispatch   = new();
      cg_lsu_clr_bsy      = new();
      cg_csr_stall        = new();
      cg_arch_valid_pattern = new();
      cg_flush_type       = new();
      // §8.2 cross
      cg_x_dispatch_occ   = new();
      cg_x_wb_commit      = new();
      cg_x_state_xcpt     = new();
      cg_x_state_misp     = new();
      cg_x_csr_commit     = new();
      cg_x_state_fence    = new();
      cg_x_dispatch_fence = new();
      cg_x_xcpt_bank      = new();
      cg_x_occ_misp       = new();
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual rob_if.MON)::get(this, "", "vif", vif))
        `uvm_fatal("COV", "No vif")
    endfunction

    function void write(rob_transaction t);
      // Triggered by monitor ap — placeholder, sampling in run_phase
    endfunction

    // ═══════════════════════════════════════════════════════════
    // Run phase: sample mỗi cycle
    // ═══════════════════════════════════════════════════════════
    task run_phase(uvm_phase phase);
      @(negedge vif.reset);
      prev_head = 0; prev_tail = 0;
      forever begin
        @(posedge vif.clock);
        do_sample();
      end
    endtask

    function void do_sample();
      // ── dispatch_width ──
      dispatch_width = 0;
      for (int i = 0; i < CW; i++)
        if (vif.mon_cb.enq_valids[i]) dispatch_width++;

      // ── partial_stall ──
      partial_stall = vif.mon_cb.enq_partial_stall;

      // ── wb_port_usage (per-port) + simultaneous_wb ──
      sim_wb_count = 0;
      for (int i = 0; i < NUM_WB_PORTS; i++) begin
        wb_port_hit[i] = vif.mon_cb.wb_resps_valid[i];
        if (wb_port_hit[i]) sim_wb_count++;
      end

      // ── commit_width ──
      commit_width = 0;
      for (int i = 0; i < CW; i++)
        if (vif.mon_cb.commit_valids[i]) commit_width++;

      // ── rob_occupancy ──
      if (vif.mon_cb.empty)
        rob_occ_pct = 0;
      else if (!vif.mon_cb.ready)
        rob_occ_pct = 100;
      else begin
        int h = vif.mon_cb.rob_head_idx;
        int t = vif.mon_cb.rob_tail_idx;
        rob_occ_pct = (t >= h) ? ((t - h) * 100) / NUM_ROB_ROWS
                                : ((NUM_ROB_ROWS - h + t) * 100) / NUM_ROB_ROWS;
        if (rob_occ_pct > 100) rob_occ_pct = 100;
        if (rob_occ_pct < 0) rob_occ_pct = 0;
      end

      // ── rob_state — Hierarchical probe ──
      // Giả định DUT signal: tb_top.dut.rob_state (2-bit register)
      // Encoding: 0=s_reset, 1=s_normal, 2=s_rollback, 3=s_wait_till_empty
      // Nếu tool hỗ trợ $root access:
      fsm_state = $root.tb_top.dut.rob_state;

      // ── exception_type ──
      // Phân loại nguồn exception dựa trên tín hiệu interface
      xcpt_type = 0; // none
      xcpt_bank = -1;
      if (vif.mon_cb.com_xcpt_valid) begin
        // Kiểm tra dispatch_xcpt: entry ở head có exception flag từ dispatch
        // Kiểm tra lxcpt: lxcpt_valid đang active hoặc vừa active
        // Mặc định: phân biệt bằng flag trên interface
        if (vif.mon_cb.lxcpt_valid)
          xcpt_type = 2; // lxcpt
        else
          xcpt_type = 1; // dispatch_xcpt (default khi com_xcpt fires)
      end
      // Tìm bank nào có exception trong head row (dùng cho cross)
      for (int b = 0; b < CW; b++) begin
        if (vif.mon_cb.enq_valids[b] && vif.mon_cb.enq_uops_exception[b]) begin
          xcpt_bank = b;
          break;
        end
      end

      // ── branch_outcome ──
      if (vif.mon_cb.brupdate_b2_mispredict)
        br_outcome = 2; // mispredict
      else if (vif.mon_cb.brupdate_b1_resolve_mask != 0
               && !vif.mon_cb.brupdate_b2_mispredict)
        br_outcome = 1; // correct resolve
      else
        br_outcome = 0; // none

      // ── pointer_wrap ──
      head_wrapped = (vif.mon_cb.rob_head_idx < prev_head && prev_head > CW);
      tail_wrapped = (vif.mon_cb.rob_tail_idx < prev_tail && prev_tail > CW
                      && !vif.mon_cb.flush_valid
                      && !vif.mon_cb.brupdate_b2_mispredict);

      // ── fence_dispatch ──
      fence_dispatched = 0;
      fence_count_in_dispatch = 0;
      for (int i = 0; i < CW; i++) begin
        if (vif.mon_cb.enq_valids[i] && vif.mon_cb.enq_uops_is_fence[i]) begin
          fence_dispatched = 1;
          fence_count_in_dispatch++;
        end
      end

      // ── lsu_clr_bsy ──
      lsu_clr_active = 0;
      for (int i = 0; i < NUM_LSU_CLR; i++)
        if (vif.mon_cb.lsu_clr_bsy_valid[i]) lsu_clr_active = 1;

      // ── csr_stall ──
      // Giờ đã thêm csr_stall vào mon_cb → sample trực tiếp
      csr_stall_active = vif.mon_cb.csr_stall;

      // ── arch_valid_pattern ──
      arch_valid_pattern = 4'b0000;
      if (commit_width > 0) begin
        for (int i = 0; i < CW; i++)
          arch_valid_pattern[i] = vif.mon_cb.commit_arch_valids[i];
      end

      // ── flush_type ──
      if (vif.mon_cb.flush_valid)
        flush_type = vif.mon_cb.flush_bits_flush_typ;
      else
        flush_type = 0;

      // ── Cross helpers ──
      has_xcpt = vif.mon_cb.com_xcpt_valid;
      has_misp = vif.mon_cb.brupdate_b2_mispredict;
      // commit_ready: ROB không empty, head row entry sẵn sàng
      // (commit_width > 0 nghĩa là đang commit, nhưng ta muốn biết "có entry ready")
      commit_ready = (!vif.mon_cb.empty && !vif.mon_cb.commit_rollback);

      // ═══════════════════════════════════════════════════════════
      // SAMPLE tất cả covergroups
      // ═══════════════════════════════════════════════════════════

      // §8.1 Functional
      cg_dispatch_width.sample();
      cg_partial_stall.sample();
      cg_wb_port_usage.sample();
      cg_simultaneous_wb.sample();
      cg_commit_width.sample();
      cg_rob_occupancy.sample();
      cg_rob_state.sample();
      cg_exception_type.sample();
      cg_branch_outcome.sample();
      cg_pointer_wrap.sample();
      cg_fence_dispatch.sample();
      cg_lsu_clr_bsy.sample();
      cg_csr_stall.sample();
      cg_arch_valid_pattern.sample();
      cg_flush_type.sample();

      // §8.2 Cross
      cg_x_dispatch_occ.sample();
      cg_x_wb_commit.sample();
      cg_x_state_xcpt.sample();
      cg_x_state_misp.sample();
      cg_x_csr_commit.sample();
      cg_x_state_fence.sample();
      cg_x_dispatch_fence.sample();
      cg_x_xcpt_bank.sample();
      cg_x_occ_misp.sample();

      // ── Update previous values ──
      prev_head = vif.mon_cb.rob_head_idx;
      prev_tail = vif.mon_cb.rob_tail_idx;
    endfunction

    // ═══════════════════════════════════════════════════════════
    // Report
    // ═══════════════════════════════════════════════════════════
    function void report_phase(uvm_phase phase);
      `uvm_info("COV", "╔══════════════════════════════════════════════╗", UVM_LOW)
      `uvm_info("COV", "║         COVERAGE REPORT (§8 Testplan)        ║", UVM_LOW)
      `uvm_info("COV", "╠══════════════════════════════════════════════╣", UVM_LOW)
      `uvm_info("COV", "║  §8.1 Functional Coverage                    ║", UVM_LOW)
      `uvm_info("COV", $sformatf("║  cg_dispatch_width    : %6.1f%%", cg_dispatch_width.get_coverage()), UVM_LOW)
      `uvm_info("COV", $sformatf("║  cg_partial_stall     : %6.1f%%", cg_partial_stall.get_coverage()), UVM_LOW)
      `uvm_info("COV", $sformatf("║  cg_wb_port_usage     : %6.1f%%", cg_wb_port_usage.get_coverage()), UVM_LOW)
      `uvm_info("COV", $sformatf("║  cg_simultaneous_wb   : %6.1f%%", cg_simultaneous_wb.get_coverage()), UVM_LOW)
      `uvm_info("COV", $sformatf("║  cg_commit_width      : %6.1f%%", cg_commit_width.get_coverage()), UVM_LOW)
      `uvm_info("COV", $sformatf("║  cg_rob_occupancy     : %6.1f%%", cg_rob_occupancy.get_coverage()), UVM_LOW)
      `uvm_info("COV", $sformatf("║  cg_rob_state         : %6.1f%%", cg_rob_state.get_coverage()), UVM_LOW)
      `uvm_info("COV", $sformatf("║  cg_exception_type    : %6.1f%%", cg_exception_type.get_coverage()), UVM_LOW)
      `uvm_info("COV", $sformatf("║  cg_branch_outcome    : %6.1f%%", cg_branch_outcome.get_coverage()), UVM_LOW)
      `uvm_info("COV", $sformatf("║  cg_pointer_wrap      : %6.1f%%", cg_pointer_wrap.get_coverage()), UVM_LOW)
      `uvm_info("COV", $sformatf("║  cg_fence_dispatch    : %6.1f%%", cg_fence_dispatch.get_coverage()), UVM_LOW)
      `uvm_info("COV", $sformatf("║  cg_lsu_clr_bsy       : %6.1f%%", cg_lsu_clr_bsy.get_coverage()), UVM_LOW)
      `uvm_info("COV", $sformatf("║  cg_csr_stall         : %6.1f%%", cg_csr_stall.get_coverage()), UVM_LOW)
      `uvm_info("COV", $sformatf("║  cg_arch_valid_pattern: %6.1f%%", cg_arch_valid_pattern.get_coverage()), UVM_LOW)
      `uvm_info("COV", $sformatf("║  cg_flush_type        : %6.1f%%", cg_flush_type.get_coverage()), UVM_LOW)
      `uvm_info("COV", "╠══════════════════════════════════════════════╣", UVM_LOW)
      `uvm_info("COV", "║  §8.2 Cross Coverage                         ║", UVM_LOW)
      `uvm_info("COV", $sformatf("║  dispatch×occupancy   : %6.1f%%", cg_x_dispatch_occ.get_coverage()), UVM_LOW)
      `uvm_info("COV", $sformatf("║  wb_count×commit      : %6.1f%%", cg_x_wb_commit.get_coverage()), UVM_LOW)
      `uvm_info("COV", $sformatf("║  rob_state×exception  : %6.1f%%", cg_x_state_xcpt.get_coverage()), UVM_LOW)
      `uvm_info("COV", $sformatf("║  rob_state×mispredict : %6.1f%%", cg_x_state_misp.get_coverage()), UVM_LOW)
      `uvm_info("COV", $sformatf("║  csr_stall×commit_rdy : %6.1f%%", cg_x_csr_commit.get_coverage()), UVM_LOW)
      `uvm_info("COV", $sformatf("║  rob_state×fence      : %6.1f%%", cg_x_state_fence.get_coverage()), UVM_LOW)
      `uvm_info("COV", $sformatf("║  dispatch×fence_count : %6.1f%%", cg_x_dispatch_fence.get_coverage()), UVM_LOW)
      `uvm_info("COV", $sformatf("║  xcpt_type×xcpt_bank  : %6.1f%%", cg_x_xcpt_bank.get_coverage()), UVM_LOW)
      `uvm_info("COV", $sformatf("║  occupancy×mispredict : %6.1f%%", cg_x_occ_misp.get_coverage()), UVM_LOW)
      `uvm_info("COV", "╚══════════════════════════════════════════════╝", UVM_LOW)
    endfunction
  endclass


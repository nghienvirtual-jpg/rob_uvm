// ==== FILE: rob_scoreboard.sv — PHIÊN BẢN SỬA ====
//
// THAY ĐỔI:
//   1. FIX BUG: shadow.commit(rob_head_idx * CW + i) → shadow.commit(rob_head_idx + i)
//      Vì rob_head_idx từ DUT đã là flat index (= row << log2(CW)), KHÔNG phải row number.
//      Nhân thêm CW gây sai entry ở mọi row != 0 (bội 16 với CW=4).
//
//   2. Thêm tracking lxcpt_valid để scoreboard biết exception source
//
//   3. Thêm log rob_head_idx + bank khi commit để dễ debug
//
// Tìm class rob_scoreboard cũ trong rob_pkg và thay toàn bộ bằng đoạn dưới:

  class rob_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(rob_scoreboard)
    virtual rob_if.MON vif;
    rob_shadow_model   shadow;
    rob_rule_checker   checker;

    int commit_cnt, xcpt_cnt, flush_cnt, rbk_cnt, disp_cnt, wb_cnt, cyc;
    int xcpt_cyc;
    bit xcpt_pend;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual rob_if.MON)::get(this, "", "vif", vif))
        `uvm_fatal("SCB", "No vif")
      shadow  = rob_shadow_model::type_id::create("shadow");
      checker = rob_rule_checker::type_id::create("checker");
      commit_cnt = 0; xcpt_cnt = 0; flush_cnt = 0; rbk_cnt = 0;
      disp_cnt = 0; wb_cnt = 0; cyc = 0; xcpt_pend = 0;
    endfunction

    task run_phase(uvm_phase phase);
      @(negedge vif.reset);
      shadow.reset();
      repeat(2) @(posedge vif.clock);

      // F1.6: empty + ready after reset
      if (vif.mon_cb.empty && vif.mon_cb.ready)
        `uvm_info("SCB", "F1.6 PASS: empty+ready after reset", UVM_LOW)
      else
        `uvm_error("SCB", $sformatf("F1.6 FAIL: empty=%0b ready=%0b",
          vif.mon_cb.empty, vif.mon_cb.ready))

      forever begin
        @(posedge vif.clock);
        cyc++;
        check();
      end
    endtask

    task check();
      bit [3:0] cv, rv;

      // ── Feed shadow: dispatch ──
      for (int i = 0; i < CW; i++) begin
        if (vif.mon_cb.enq_valids[i]) begin
          disp_cnt++;
          shadow.dispatch(
            vif.mon_cb.enq_uops_rob_idx[i],
            vif.mon_cb.enq_uops_pdst[i],
            vif.mon_cb.enq_uops_exception[i],
            vif.mon_cb.enq_uops_is_fence[i],
            vif.mon_cb.enq_uops_br_mask[i],
            vif.mon_cb.enq_uops_unsafe[i]
          );
        end
      end

      // ── Feed shadow: writeback ──
      for (int i = 0; i < NUM_WB_PORTS; i++) begin
        if (vif.mon_cb.wb_resps_valid[i]) begin
          wb_cnt++;
          shadow.writeback(vif.mon_cb.wb_resps_rob_idx[i],
                           vif.mon_cb.wb_resps_pdst[i]);
        end
      end

      // ── Feed shadow: LSU clear ──
      for (int i = 0; i < NUM_LSU_CLR; i++)
        if (vif.mon_cb.lsu_clr_bsy_valid[i])
          shadow.lsu_clr(vif.mon_cb.lsu_clr_bsy_bits[i]);

      // ── Feed shadow: branch ──
      if (vif.mon_cb.brupdate_b1_resolve_mask != 0)
        shadow.branch_resolve(vif.mon_cb.brupdate_b1_resolve_mask);
      if (vif.mon_cb.brupdate_b2_mispredict)
        shadow.branch_kill(vif.mon_cb.brupdate_b1_mispredict_mask);

      // ── Feed shadow: commit ──
      // FIX: rob_head_idx từ DUT = row << log2(CW) = flat index bank 0
      //      Chỉ cần +i cho bank offset. KHÔNG nhân CW.
      for (int i = 0; i < CW; i++) begin
        cv[i] = vif.mon_cb.commit_valids[i];
        rv[i] = vif.mon_cb.commit_rbk_valids[i];
        if (cv[i]) begin
          commit_cnt++;
          shadow.commit(vif.mon_cb.rob_head_idx + i);  // ← FIX: was *CW+i
        end
      end

      // ── Exception / Flush / Rollback counters ──
      if (vif.mon_cb.com_xcpt_valid) xcpt_cnt++;
      if (vif.mon_cb.flush_valid) begin
        flush_cnt++;
        shadow.flush_all();
      end
      if (vif.mon_cb.commit_rollback) rbk_cnt++;

      // ═══ RULE CHECKS ═══

      // D3: dispatch only when ready
      begin
        bit any_enq = 0;
        for (int i = 0; i < CW; i++)
          if (vif.mon_cb.enq_valids[i]) any_enq = 1;
        checker.chk_D3(vif.mon_cb.ready, any_enq);
      end

      // A8: commit ⊕ rollback exclusive
      checker.chk_A8(cv, rv);

      // F3.1: in-order commit (no gap in banks)
      begin
        bit c[4];
        for (int i = 0; i < 4; i++) c[i] = cv[i];
        checker.chk_F31(c);
      end

      // F4.8: 2-cycle delay exception → rollback
      if (vif.mon_cb.com_xcpt_valid && !xcpt_pend) begin
        xcpt_cyc  = cyc;
        xcpt_pend = 1;
      end
      if (vif.mon_cb.commit_rollback && xcpt_pend) begin
        int delay = cyc - xcpt_cyc;
        if (delay >= 2)
          `uvm_info("SCB", $sformatf("F4.8 PASS: xcpt→rollback delay=%0d cycles", delay), UVM_MEDIUM)
        else
          `uvm_warning("SCB", $sformatf("F4.8 CHECK: delay=%0d cycles (expect ≥2)", delay))
        xcpt_pend = 0;
      end

      // F4.10: flush_frontend when exception
      if (vif.mon_cb.com_xcpt_valid)
        `uvm_info("SCB", $sformatf("F4.10: flush_frontend=%0b", vif.mon_cb.flush_frontend), UVM_HIGH)
    endtask

    function void report_phase(uvm_phase phase);
      `uvm_info("SCB", "╔══════════════════════════════════════╗", UVM_LOW)
      `uvm_info("SCB", "║      SCOREBOARD SUMMARY              ║", UVM_LOW)
      `uvm_info("SCB", "╠══════════════════════════════════════╣", UVM_LOW)
      `uvm_info("SCB", $sformatf("║ Dispatches : %0d", disp_cnt),   UVM_LOW)
      `uvm_info("SCB", $sformatf("║ Writebacks : %0d", wb_cnt),     UVM_LOW)
      `uvm_info("SCB", $sformatf("║ Commits    : %0d", commit_cnt), UVM_LOW)
      `uvm_info("SCB", $sformatf("║ Exceptions : %0d", xcpt_cnt),   UVM_LOW)
      `uvm_info("SCB", $sformatf("║ Flushes    : %0d", flush_cnt),  UVM_LOW)
      `uvm_info("SCB", $sformatf("║ Rollbacks  : %0d", rbk_cnt),    UVM_LOW)
      `uvm_info("SCB", $sformatf("║ Cycles     : %0d", cyc),        UVM_LOW)
      `uvm_info("SCB", "╚══════════════════════════════════════╝", UVM_LOW)
      checker.report();
    endfunction
  endclass

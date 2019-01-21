(*
 * Copyright 2014, General Dynamics C4 Systems
 *
 * This software may be distributed and modified according to the terms of
 * the GNU General Public License version 2. Note that NO WARRANTY is provided.
 * See "LICENSE_GPLv2.txt" for details.
 *
 * @TAG(GD_GPL)
 *)

(*
Invariant preservation for all syscalls.
*)

theory Syscall_AI
imports
  "./$L4V_ARCH/ArchBCorres2_AI"
  "./$L4V_ARCH/ArchTcb_AI"
  "./$L4V_ARCH/ArchArch_AI"
  "./$L4V_ARCH/ArchInterrupt_AI"
begin

context begin interpretation Arch .
requalify_facts
  arch_decode_invocation_inv
  lookup_cap_and_slot_inv
  data_to_cptr_def
  arch_post_cap_deletion_cur_thread
  arch_post_cap_deletion_state_refs_of
end

lemmas [wp] =
  arch_decode_invocation_inv
  lookup_cap_and_slot_inv

lemmas [simp] =
  data_to_cptr_def


lemma next_domain_invs[wp]:
  "next_domain \<lbrace> invs \<rbrace>"
  unfolding next_domain_def
  apply (wpsimp simp: Let_def)
  apply (simp add: invs_def cur_tcb_def valid_state_def valid_mdb_def mdb_cte_at_def valid_ioc_def
                   valid_irq_states_def valid_machine_state_def)
  done

lemma awaken_invs[wp]:
  "awaken \<lbrace> invs \<rbrace>"
  unfolding awaken_def by (wpsimp wp: mapM_x_wp')

lemma schedule_invs[wp]: "\<lbrace>invs\<rbrace> Schedule_A.schedule \<lbrace>\<lambda>rv. invs\<rbrace>"
  supply if_split[split del]
  apply (simp add: Schedule_A.schedule_def)
  apply (wp dmo_invs thread_get_inv gts_wp sc_and_timer_invs
            do_machine_op_tcb when_def hoare_vcg_all_lift
          | wpc
          | clarsimp simp: guarded_switch_to_def get_tcb_def choose_thread_def thread_get_def
          | wp_once hoare_drop_imps
          | simp add: schedule_choose_new_thread_def if_apply_def2)+
  done

(* FIXME: replace the one in KHeap_AI! *)
lemma is_schedulable_wp:
  "\<lbrace>\<lambda>s. \<forall>t. is_schedulable_opt x inq s = Some t \<longrightarrow> P t s\<rbrace> is_schedulable x inq \<lbrace>P\<rbrace>"
  apply (clarsimp simp: is_schedulable_def)
  apply (rule hoare_seq_ext[OF _ assert_get_tcb_ko'])
  apply (case_tac "tcb_sched_context tcb"; clarsimp)
   apply (wpsimp simp: is_schedulable_opt_def obj_at_def get_tcb_rev)
  by (wpsimp simp: is_schedulable_opt_def obj_at_def get_tcb_rev test_sc_refill_max_def
               wp: get_sched_context_wp)

lemma invs_domain_time_update[simp]:
  "invs (domain_time_update f s) = invs s"
  by (simp add: invs_def valid_state_def)

lemma invs_domain_index_update[simp]:
  "invs (domain_index_update f s) = invs s"
  by (simp add: invs_def valid_state_def valid_mdb_def mdb_cte_at_def valid_ioc_def
                valid_irq_states_def valid_machine_state_def cur_tcb_def)

lemma invs_cur_domain_update[simp]:
  "invs (cur_domain_update f s) = invs s"
  by (simp add: invs_def valid_state_def valid_mdb_def mdb_cte_at_def valid_ioc_def
                valid_irq_states_def valid_machine_state_def cur_tcb_def)

lemma choose_thread_ct_activatable[wp]:
  "\<lbrace> invs \<rbrace> choose_thread \<lbrace>\<lambda>_. ct_in_state activatable \<rbrace>"
proof -
  have P: "\<And>t s. ct_in_state activatable (cur_thread_update (\<lambda>_. t) s) = st_tcb_at activatable t s"
    by (fastforce simp: ct_in_state_def st_tcb_at_def intro: obj_at_pspaceI)
  show ?thesis
    unfolding choose_thread_def guarded_switch_to_def
    apply (wpsimp wp: stit_activatable stt_activatable split_del: if_split wp_del: get_sched_context_wp)
            apply (wpsimp wp: hoare_drop_imp hoare_vcg_all_lift)
           apply (wpsimp wp: assert_wp)
          apply (wpsimp simp: thread_get_def)+
        apply (wpsimp wp: is_schedulable_wp)
       apply (wpsimp wp: hoare_vcg_all_lift)+
    apply (clarsimp simp: is_schedulable_opt_def pred_tcb_at_def obj_at_def
        dest!: get_tcb_SomeD split: option.splits)
    done
qed

lemma schedule_choose_new_thread_ct_activatable[wp]:
  "\<lbrace> invs \<rbrace> schedule_choose_new_thread \<lbrace>\<lambda>_. ct_in_state activatable \<rbrace>"
    unfolding schedule_choose_new_thread_def by wpsimp

lemma guarded_switch_to_ct_in_state_activatable[wp]:
  "\<lbrace>\<top>\<rbrace> guarded_switch_to t \<lbrace>\<lambda>a. ct_in_state activatable\<rbrace>"
  unfolding guarded_switch_to_def
  apply (wpsimp wp: hoare_vcg_imp_lift gts_wp is_schedulable_wp stt_activatable assert_wp
             simp: thread_get_def)
  apply (clarsimp simp: is_schedulable_opt_def get_tcb_ko_at st_tcb_at_def obj_at_def
                 split: option.splits)
  done

declare sc_and_timer_activatable[wp]

lemma schedule_ct_activateable[wp]:
  "\<lbrace>invs\<rbrace> Schedule_A.schedule \<lbrace>\<lambda>rv. ct_in_state activatable\<rbrace>"
  supply if_split [split del]
  apply (simp add: Schedule_A.schedule_def)
  apply wp
        apply wpc
          (* resume current thread *)
          apply wp
         prefer 2
         (* choose new thread *)
         apply wp
        (* switch to thread *)
        apply (wpsimp simp: schedule_switch_thread_fastfail_def tcb_sched_action_def
                            set_tcb_queue_def get_tcb_queue_def
                        wp: thread_get_wp')
       apply (wp add: is_schedulable_wp)+
   apply (rule hoare_strengthen_post[where Q="\<lambda>_. invs"], wp)
   apply clarsimp
   apply (frule invs_valid_idle)
   apply (clarsimp simp: ct_in_state_def pred_tcb_at_def obj_at_def valid_idle_def
                         is_schedulable_opt_def get_tcb_ko_at
                  split: option.splits if_split)
  apply assumption
  done

lemma syscall_valid:
  assumes x:
             "\<And>ft. \<lbrace>P_flt ft\<rbrace> h_flt ft \<lbrace>Q\<rbrace>"
             "\<And>err. \<lbrace>P_err err\<rbrace> h_err err \<lbrace>Q\<rbrace>"
             "\<And>rv. \<lbrace>P_no_err rv\<rbrace> m_fin rv \<lbrace>Q\<rbrace>,\<lbrace>E\<rbrace>"
             "\<And>rv. \<lbrace>P_no_flt rv\<rbrace> m_err rv \<lbrace>P_no_err\<rbrace>, \<lbrace>P_err\<rbrace>"
             "\<lbrace>P\<rbrace> m_flt \<lbrace>P_no_flt\<rbrace>, \<lbrace>P_flt\<rbrace>"
  shows "\<lbrace>P\<rbrace> Syscall_A.syscall m_flt h_flt m_err h_err m_fin \<lbrace>Q\<rbrace>, \<lbrace>E\<rbrace>"
  apply (simp add: Syscall_A.syscall_def liftE_bindE
             cong: sum.case_cong)
  apply (rule hoare_split_bind_case_sumE)
    apply (wp x)[1]
   apply (rule hoare_split_bind_case_sumE)
     apply (wp x|simp)+
  done


(* In order to assert conditions that must hold for the appropriate
   handleInvocation and handle_invocation calls to succeed, we must have
   some notion of what a valid invocation is.
   This function defines that.
   For example, a InvokeEndpoint requires an endpoint at its first
   constructor argument. *)

primrec
  valid_invocation :: "Invocations_A.invocation \<Rightarrow> 'z::state_ext state \<Rightarrow> bool"
where
  "valid_invocation (InvokeUntyped i) = valid_untyped_inv i"
| "valid_invocation (InvokeEndpoint w w2 b) = (ep_at w and ex_nonz_cap_to w)"
| "valid_invocation (InvokeNotification w w2) = (ntfn_at w and ex_nonz_cap_to w)"
| "valid_invocation (InvokeTCB i) = Tcb_AI.tcb_inv_wf i"
| "valid_invocation (InvokeDomain thread domain) = (tcb_at thread and (\<lambda>s. thread \<noteq> idle_thread s))"
| "valid_invocation (InvokeReply reply) = (reply_at reply and ex_nonz_cap_to reply)"
| "valid_invocation (InvokeIRQControl i) = irq_control_inv_valid i"
| "valid_invocation (InvokeIRQHandler i) = irq_handler_inv_valid i"
| "valid_invocation (InvokeCNode i) = valid_cnode_inv i"
| "valid_invocation (InvokeSchedContext i) = valid_sched_context_inv i"
| "valid_invocation (InvokeSchedControl i) = valid_sched_control_inv i"
| "valid_invocation (InvokeArchObject i) = valid_arch_inv i"

lemma sts_Restart_invs[wp]:
  "\<lbrace>st_tcb_at active t and invs and ex_nonz_cap_to t\<rbrace>
     set_thread_state t Structures_A.Restart
   \<lbrace>\<lambda>rv. invs\<rbrace>"
  apply (wp sts_invs_minor2)
  apply (auto elim!: pred_tcb_weakenE
           notE [rotated, OF _ idle_no_ex_cap]
           simp: invs_def valid_state_def valid_pspace_def)
  done

lemma check_budget_restart_invs[wp]:
  "\<lbrace>\<lambda>s. invs s\<rbrace> check_budget_restart \<lbrace>\<lambda>rv. invs\<rbrace>"
  apply (clarsimp simp: check_budget_restart_def)
  apply (rule hoare_seq_ext[rotated])
   apply (rule check_budget_invs)
  apply (wpsimp wp: gts_wp)
  apply (case_tac st; wpsimp)
   apply (drule invs_iflive,
          clarsimp simp: if_live_then_nonz_cap_def pred_tcb_at_def obj_at_def live_def)+
  done

lemma invoke_tcb_tcb[wp]:
  "invoke_tcb i \<lbrace>tcb_at tptr::det_state\<Rightarrow>_\<rbrace>"
  by (simp add: tcb_at_typ, rule invoke_tcb_typ_at [where P=id, simplified])

lemma invoke_domain_tcb[wp]:
  "\<lbrace>tcb_at tptr\<rbrace> invoke_domain thread domain \<lbrace>\<lambda>rv. tcb_at tptr\<rbrace>"
  by (simp add: tcb_at_typ invoke_domain_typ_at [where P=id, simplified])

lemma simple_from_active:
  "st_tcb_at active t s \<Longrightarrow> st_tcb_at simple t s"
  by (fastforce elim!: pred_tcb_weakenE)

lemma simple_from_running:
  "ct_running s \<Longrightarrow> st_tcb_at simple (cur_thread s) s"
  by (fastforce simp: ct_in_state_def
               elim!: pred_tcb_weakenE)

locale Systemcall_AI_Pre =
  fixes proj:: "itcb \<Rightarrow> 'a"
  fixes state_ext_t :: "'state_ext::state_ext itself"
  assumes handle_arch_fault_reply_pred_tcb_at[wp]:
    "\<And> P t f obj d dl.
      \<lbrace> pred_tcb_at proj P t :: 'state_ext state \<Rightarrow> _\<rbrace>
        handle_arch_fault_reply f obj d dl
      \<lbrace> \<lambda>_ . pred_tcb_at proj P t \<rbrace>"
  assumes handle_arch_fault_reply_invs[wp]:
    "\<And> f obj d dl.
      \<lbrace> invs :: 'state_ext state \<Rightarrow> _ \<rbrace> handle_arch_fault_reply f obj d dl \<lbrace> \<lambda>_ . invs \<rbrace>"
  assumes handle_arch_fault_reply_cap_to[wp]:
    "\<And> f obj d dl c.
      \<lbrace> ex_nonz_cap_to c :: 'state_ext state \<Rightarrow> _ \<rbrace>
        handle_arch_fault_reply f obj d dl
      \<lbrace> \<lambda>_ . ex_nonz_cap_to c \<rbrace>"
  assumes handle_arch_fault_reply_it[wp]:
    "\<And> P f obj d dl.
      \<lbrace> \<lambda>s :: 'state_ext state. P (idle_thread s) \<rbrace>
        handle_arch_fault_reply f obj d dl
      \<lbrace> \<lambda>_ s. P (idle_thread s) \<rbrace>"
  assumes handle_arch_fault_reply_caps[wp]:
    "\<And> P f obj d dl.
      \<lbrace> \<lambda>s  :: 'state_ext state . P (caps_of_state s) \<rbrace>
        handle_arch_fault_reply f obj d dl
      \<lbrace> \<lambda>_ s. P (caps_of_state s) \<rbrace>"
  assumes handle_arch_fault_reply_cte_wp_at[wp]:
     "\<And> P P' p x4 t d dl.
       \<lbrace>\<lambda>s ::'state_ext state . P (cte_wp_at P' p s)\<rbrace>
         handle_arch_fault_reply x4 t d dl
       \<lbrace>\<lambda>_ s. P (cte_wp_at P' p s)\<rbrace>"
  assumes handle_arch_fault_reply_cur_thread[wp]:
    "\<And> P  x4 t d dl.
       \<lbrace>\<lambda>s ::'state_ext state . P (cur_thread s)\<rbrace>
         handle_arch_fault_reply x4 t d dl
       \<lbrace>\<lambda>_ s. P (cur_thread s)\<rbrace>"
  assumes handle_arch_fault_st_tcb_at_simple[wp]:
    "\<And> x4 t' t d dl.
       \<lbrace>st_tcb_at simple t' :: 'state_ext state \<Rightarrow> _\<rbrace>
         handle_arch_fault_reply x4 t d dl
       \<lbrace>\<lambda>_ .st_tcb_at simple t'\<rbrace>"
  assumes handle_arch_fault_valid_objs[wp]:
    "\<And> x4 t d dl.
       \<lbrace> valid_objs :: 'state_ext state \<Rightarrow> _\<rbrace>
         handle_arch_fault_reply x4 t d dl
       \<lbrace>\<lambda>_ .valid_objs\<rbrace>"
  assumes arch_get_sanitise_register_info_pred_tcb_at[wp]:
    "\<And> P t g.
      \<lbrace> pred_tcb_at proj P t :: 'state_ext state \<Rightarrow> _\<rbrace>
        arch_get_sanitise_register_info g
      \<lbrace> \<lambda>_ . pred_tcb_at proj P t \<rbrace>"
  assumes arch_get_sanitise_register_info_invs[wp]:
    "\<And> f.
      \<lbrace> invs :: 'state_ext state \<Rightarrow> _ \<rbrace> arch_get_sanitise_register_info f  \<lbrace> \<lambda>_ . invs \<rbrace>"
  assumes arch_get_sanitise_register_info_cap_to[wp]:
    "\<And> f c.
      \<lbrace> ex_nonz_cap_to c :: 'state_ext state \<Rightarrow> _ \<rbrace>
        arch_get_sanitise_register_info f
      \<lbrace> \<lambda>_ . ex_nonz_cap_to c \<rbrace>"
  assumes arch_get_sanitise_register_info_it[wp]:
    "\<And> P f .
      \<lbrace> \<lambda>s :: 'state_ext state. P (idle_thread s) \<rbrace>
        arch_get_sanitise_register_info f
      \<lbrace> \<lambda>_ s. P (idle_thread s) \<rbrace>"
  assumes arch_get_sanitise_register_info_caps[wp]:
    "\<And> P f .
      \<lbrace> \<lambda>s  :: 'state_ext state . P (caps_of_state s) \<rbrace>
        arch_get_sanitise_register_info f
      \<lbrace> \<lambda>_ s. P (caps_of_state s) \<rbrace>"
  assumes arch_get_sanitise_register_info_cte_wp_at[wp]:
     "\<And> P P' p x4.
       \<lbrace>\<lambda>s ::'state_ext state . P (cte_wp_at P' p s)\<rbrace>
         arch_get_sanitise_register_info x4
       \<lbrace>\<lambda>_ s. P (cte_wp_at P' p s)\<rbrace>"
  assumes arch_get_sanitise_register_info_cur_thread[wp]:
    "\<And> P  x4.
       \<lbrace>\<lambda>s ::'state_ext state . P (cur_thread s)\<rbrace>
         arch_get_sanitise_register_info x4
       \<lbrace>\<lambda>_ s. P (cur_thread s)\<rbrace>"
  assumes arch_get_sanitise_register_info_st_tcb_at_simple[wp]:
    "\<And> x4 t'.
       \<lbrace>st_tcb_at simple t' :: 'state_ext state \<Rightarrow> _\<rbrace>
         arch_get_sanitise_register_info x4
       \<lbrace>\<lambda>_ .st_tcb_at simple t'\<rbrace>"
  assumes arch_get_sanitise_register_info_valid_objs[wp]:
    "\<And> x4.
       \<lbrace> valid_objs :: 'state_ext state \<Rightarrow> _\<rbrace>
         arch_get_sanitise_register_info x4
       \<lbrace>\<lambda>_ .valid_objs\<rbrace>"

begin

crunch pred_tcb_at[wp]: handle_fault_reply "pred_tcb_at proj (P :: 'a \<Rightarrow> _) t :: 'state_ext state \<Rightarrow> _"
crunch invs[wp]: handle_fault_reply "invs :: 'state_ext state \<Rightarrow> _"
crunch cap_to[wp]: handle_fault_reply "ex_nonz_cap_to c :: 'state_ext state \<Rightarrow> _"
crunch it[wp]: handle_fault_reply "\<lambda>s :: 'state_ext state. P (idle_thread s) "
crunch caps[wp]: handle_fault_reply "\<lambda>s :: 'state_ext state. P (caps_of_state s)"

end

lemma st_tcb_at_eq:
  "\<lbrakk> st_tcb_at (\<lambda>s. s = st) t s; st_tcb_at (\<lambda>s. s = st') t s \<rbrakk> \<Longrightarrow> st = st'"
  by (clarsimp simp add: pred_tcb_at_def obj_at_def)

lemma do_ipc_transfer_tcb_at [wp]:
  "\<lbrace>\<lambda>s. P (tcb_at t s)\<rbrace> do_ipc_transfer s ep bg grt r \<lbrace>\<lambda>rv s. P (tcb_at t s)\<rbrace>"
  by (simp add: tcb_at_typ) wp

lemma do_ipc_transfer_non_null_cte_wp_at2:
  fixes P
  assumes PNN: "\<And>cap. P cap \<Longrightarrow> cap \<noteq> cap.NullCap"
  assumes PUC: "\<And>cap. P cap \<Longrightarrow> \<not> is_untyped_cap cap"
  shows "\<lbrace>valid_objs and cte_wp_at P ptr\<rbrace> do_ipc_transfer st ep b gr rt \<lbrace>\<lambda>_. cte_wp_at P ptr\<rbrace>"
  proof -
    have PimpQ: "\<And>P Q ptr s. \<lbrakk> cte_wp_at P ptr s; \<And>cap. P cap \<Longrightarrow> Q cap \<rbrakk> \<Longrightarrow> cte_wp_at (P and Q) ptr s"
      by (erule cte_wp_at_weakenE, clarsimp)
    show ?thesis
      apply (rule hoare_chain [OF do_ipc_transfer_non_null_cte_wp_at])
       apply (erule PUC)
       apply (clarsimp )
       apply (erule PimpQ)
       apply (drule PNN, clarsimp)
      apply (erule cte_wp_at_weakenE)
      apply (clarsimp)
      done
  qed


lemma thread_set_cap_to:
  "(\<And>tcb. \<forall>(getF, v)\<in>ran tcb_cap_cases. getF (f tcb) = getF tcb)
  \<Longrightarrow> \<lbrace>ex_nonz_cap_to p\<rbrace> thread_set f tptr \<lbrace>\<lambda>_. ex_nonz_cap_to p\<rbrace>"
  apply (clarsimp simp add: ex_nonz_cap_to_def)
  apply (wpsimp wp: hoare_ex_wp thread_set_cte_wp_at_trivial
    | fast)+
  done


lemma thread_set_has_no_reply_cap:
  "(\<And>tcb. \<forall>(getF, v)\<in>ran tcb_cap_cases. getF (f tcb) = getF tcb)
  \<Longrightarrow> \<lbrace>\<lambda>s. \<not>has_reply_cap tt s\<rbrace> thread_set f t \<lbrace>\<lambda>_ s. \<not>has_reply_cap tt s\<rbrace>"
  apply (clarsimp simp add: has_reply_cap_def)
  apply (wpsimp wp: hoare_vcg_all_lift thread_set_cte_wp_at_trivial
    | fast)+
  done


lemma set_object_cte_wp_at2:
  "\<lbrace>\<lambda>s. P (cte_wp_at P' p (s\<lparr>kheap := kheap s(ptr \<mapsto> ko)\<rparr>))\<rbrace> set_object ptr ko \<lbrace>\<lambda>_ s. P (cte_wp_at P' p s)\<rbrace>"
  unfolding set_object_def by wp


lemma (in Systemcall_AI_Pre) handle_fault_reply_cte_wp_at:
  "\<lbrace>\<lambda>s :: 'state_ext state. P (cte_wp_at P' p s)\<rbrace>
     handle_fault_reply f t d dl
   \<lbrace>\<lambda>_ s. P (cte_wp_at P' p s)\<rbrace>"
  proof -
    have SC:
      "\<And>p' s tcb nc. get_tcb p' s = Some tcb
       \<Longrightarrow> obj_at (same_caps (TCB (tcb \<lparr>tcb_arch := arch_tcb_context_set nc (tcb_arch tcb)\<rparr>))) p' s"
      apply (drule get_tcb_ko_at [THEN iffD1])
      apply (erule ko_at_weakenE)
      apply (clarsimp simp add: tcb_cap_cases_def)
      done
    have NC:
      "\<And>p' s tcb P nc. get_tcb p' s = Some tcb
      \<Longrightarrow> cte_wp_at P p (s\<lparr>kheap := kheap s(p' \<mapsto> TCB (tcb\<lparr>tcb_arch := arch_tcb_context_set nc (tcb_arch tcb)\<rparr>))\<rparr>)
          = cte_wp_at P p s"
      apply (drule_tac nc=nc in SC)
      apply (drule_tac P=P and p=p in cte_wp_at_after_update)
      apply (drule sym)
      apply (clarsimp)
      apply (rule_tac x="s \<lparr> kheap := p \<rparr>" for p in arg_cong)
      apply (clarsimp)
      done
    show ?thesis
      apply (case_tac f; clarsimp simp: as_user_def)
       apply (wp set_object_cte_wp_at2 thread_get_wp' | simp add: split_def NC | wp_once hoare_drop_imps)+
      done
  qed


lemma (in Systemcall_AI_Pre) handle_fault_reply_has_no_reply_cap:
  "\<lbrace>\<lambda>s :: 'state_ext state. \<not>has_reply_cap t s\<rbrace> handle_fault_reply f t d dl \<lbrace>\<lambda>_ s. \<not>has_reply_cap t s\<rbrace>"
  apply (clarsimp simp add: has_reply_cap_def)
  apply (wpsimp wp: hoare_vcg_all_lift handle_fault_reply_cte_wp_at)
  done

crunches refill_unblock_check
  for st_tcb_at[wp]: "\<lambda>s. P (st_tcb_at Q t s)"
  and pred_tcb[wp]: "\<lambda>s. P (pred_tcb_at f Q t s)"
  (wp: crunch_wps hoare_vcg_if_lift2)

lemmas si_invs[wp] = si_invs'[where Q=\<top>,OF hoare_TrueI hoare_TrueI hoare_TrueI hoare_TrueI,simplified]

locale Systemcall_AI_Pre2 = Systemcall_AI_Pre itcb_state state_ext_t
  for state_ext_t :: "'state_ext::state_ext itself"
begin

lemma do_reply_invs[wp]:
  "\<lbrace>tcb_at t and reply_at r and invs\<rbrace>
     do_reply_transfer t r
   \<lbrace>\<lambda>rv. invs :: 'state_ext state \<Rightarrow> bool\<rbrace>"
  apply (simp add: do_reply_transfer_def)
  apply (wpsimp wp: sts_invs_minor2_concise handle_timeout_Timeout_invs hoare_drop_imps
                    hoare_vcg_all_lift refill_unblock_check_invs)
                apply (wpsimp wp: get_tcb_obj_ref_wp)
               apply (rule_tac
                        Q = "\<lambda>_ s. invs s \<and> (restart \<longrightarrow> st_tcb_at active x s)"
                      in hoare_strengthen_post[rotated])
                apply (clarsimp simp: pred_tcb_at_def obj_at_def)
               apply (wpsimp wp: sts_st_tcb_at' sts_invs_minor | rule conjI)+
               apply (wpsimp wp: thread_set_cap_to thread_set_invs_trivial
                                 thread_set_no_change_tcb_state gts_wp
                                 hoare_drop_imps reply_remove_invs get_simple_ko_wp
                           simp: ran_tcb_cap_cases)+
  apply (clarsimp simp: pred_tcb_at_eq_commute)
  apply (clarsimp simp: reply_tcb_reply_at_def obj_at_def pred_tcb_at_def is_tcb is_reply)
  apply (frule invs_valid_idle)
  apply (fastforce simp: valid_idle_def pred_tcb_at_def obj_at_def live_def
                 intro!: if_live_then_nonz_cap_invs)
  done

lemma pinv_invs[wp]:
  "\<lbrace>\<lambda>s. invs s \<and> ct_active s \<and> valid_invocation i s \<and> bound_sc_tcb_at bound (cur_thread s) s\<rbrace>
    perform_invocation blocking call can_donate i \<lbrace>\<lambda>rv. invs :: 'state_ext state \<Rightarrow> _\<rbrace>"
  apply (cases i
         ; wpsimp wp: tcbinv_invs send_signal_interrupt_states invoke_domain_invs
                simp: ct_in_state_def)
  apply (erule st_tcb_ex_cap; fastforce)
  done

end

lemma do_reply_transfer_typ_at[wp]:
  "do_reply_transfer s r \<lbrace>\<lambda>s. P (typ_at T p s)\<rbrace>"
  unfolding do_reply_transfer_def
  by (wpsimp wp: gts_wp hoare_vcg_if_lift2 hoare_drop_imps hoare_vcg_all_lift split_del: if_split)

crunch typ_at[wp]: invoke_irq_handler "\<lambda>s. P (typ_at T p s)"


locale Syscall_AI = Systemcall_AI_Pre:Systemcall_AI_Pre _ state_ext_t
                  + Systemcall_AI_Pre2 state_ext_t
  for state_ext_t :: "'state_ext::state_ext itself" +
  assumes invoke_irq_control_typ_at[wp]:
    "\<And>P T p irq_inv.
      \<lbrace>\<lambda>s::det_ext state. P (typ_at T p s)\<rbrace> invoke_irq_control irq_inv \<lbrace>\<lambda>_ s. P (typ_at T p s)\<rbrace>"
  assumes obj_refs_cap_rights_update[simp]:
    "\<And>rs cap. obj_refs (cap_rights_update rs cap) = obj_refs cap"
  assumes table_cap_ref_mask_cap:
    "\<And>R cap. table_cap_ref (mask_cap R cap) = table_cap_ref cap"
  assumes diminished_no_cap_to_obj_with_diff_ref:
    "\<And>cap p (s::det_ext state) S.
      \<lbrakk> cte_wp_at (diminished cap) p s; valid_arch_caps s \<rbrakk>
        \<Longrightarrow> no_cap_to_obj_with_diff_ref cap S s"
  assumes hv_invs[wp]:
    "\<And>t' flt. \<lbrace>invs :: 'state_ext state \<Rightarrow> bool\<rbrace> handle_vm_fault t' flt \<lbrace>\<lambda>r. invs\<rbrace>"
  assumes handle_vm_fault_valid_fault[wp]:
    "\<And>thread ft.
      \<lbrace>\<top>::'state_ext state \<Rightarrow> bool\<rbrace> handle_vm_fault thread ft -,\<lbrace>\<lambda>rv s. valid_fault rv\<rbrace>"
  assumes hvmf_active:
    "\<And>t w.
      \<lbrace>st_tcb_at active t::'state_ext state \<Rightarrow> bool\<rbrace> handle_vm_fault t w \<lbrace>\<lambda>rv. st_tcb_at active t\<rbrace>"
  assumes hvmf_ex_cap[wp]:
    "\<And>p t b.
      \<lbrace>ex_nonz_cap_to p::'state_ext state \<Rightarrow> bool\<rbrace> handle_vm_fault t b \<lbrace>\<lambda>rv. ex_nonz_cap_to p\<rbrace>"
  assumes hh_invs[wp]:
  "\<And>thread fault.
    \<lbrace>invs and ct_active and st_tcb_at active thread and ex_nonz_cap_to thread\<rbrace>
      handle_hypervisor_fault thread fault
    \<lbrace>\<lambda>rv. invs :: 'state_ext state \<Rightarrow> bool\<rbrace>"
  assumes make_fault_msg_cur_thread[wp]:
    "\<And>ft t. make_fault_msg ft t \<lbrace>\<lambda>s :: 'state_ext state. P (cur_thread s)\<rbrace>"




context Syscall_AI begin

lemma pinv_tcb[wp]:
  "\<And>tptr blocking call can_donate i.
    \<lbrace>invs and st_tcb_at active tptr and ct_active and valid_invocation i\<rbrace>
      perform_invocation blocking call can_donate i
    \<lbrace>\<lambda>rv. tcb_at tptr :: det_ext state \<Rightarrow> bool\<rbrace>"
  apply (case_tac i, simp_all split:option.splits)
             apply (wpsimp simp: st_tcb_at_tcb_at)+
            apply ((wpsimp wp: tcb_at_typ_at simp: st_tcb_at_tcb_at)+)[3]
         apply ((wpsimp simp: st_tcb_at_tcb_at)+)[5]
    apply ((simp add: tcb_at_typ, wpsimp simp: st_tcb_at_tcb_at tcb_at_typ[symmetric])+)[2]
  apply (wpsimp wp: invoke_arch_tcb)
  done

end


lemmas sts_typ_at = set_thread_state_typ_at [where P="\<lambda>x. x"]

lemma cte_wp_cdt_lift:
  assumes c: "\<And>P. \<lbrace>cte_wp_at P p\<rbrace> f \<lbrace>\<lambda>r. cte_wp_at P p\<rbrace>"
  assumes m: "\<And>P. \<lbrace>\<lambda>s. P (cdt s)\<rbrace> f \<lbrace>\<lambda>r s. P (cdt s)\<rbrace>"
  shows "\<lbrace>\<lambda>s. cte_wp_at (P (cdt s)) p s\<rbrace> f \<lbrace>\<lambda>r s. cte_wp_at (P (cdt s)) p s\<rbrace>"
  apply (clarsimp simp add: valid_def)
  apply (frule_tac P1="(=) (cdt s)" in use_valid [OF _  m], rule refl)
  apply simp
  apply (erule use_valid [OF _ c])
  apply simp
  done

lemma sts_cte_wp_cdt [wp]:
  "\<lbrace>\<lambda>s. cte_wp_at (P (cdt s)) p s\<rbrace>
  set_thread_state t st
  \<lbrace>\<lambda>rv s. cte_wp_at (P (cdt s)) p s\<rbrace>"
  by (rule cte_wp_cdt_lift; wp)

lemma sts_nasty_bit:
  shows
  "\<lbrace>\<lambda>s. \<forall>r\<in>obj_refs cap. \<forall>a b. ptr' \<noteq> (a, b) \<and> cte_wp_at (\<lambda>cap'. r \<in> obj_refs cap') (a, b) s
              \<longrightarrow> cte_wp_at (Not \<circ> is_zombie) (a, b) s \<and> \<not> is_zombie cap\<rbrace>
     set_thread_state t st
   \<lbrace>\<lambda>rv s. \<forall>r\<in>obj_refs cap. \<forall>a b. ptr' \<noteq> (a, b) \<and> cte_wp_at (\<lambda>cap'. r \<in> obj_refs cap') (a, b) s
              \<longrightarrow> cte_wp_at (Not \<circ> is_zombie) (a, b) s \<and> \<not> is_zombie cap\<rbrace>"
  apply (intro hoare_vcg_const_Ball_lift hoare_vcg_all_lift)
  apply (wpsimp wp: hoare_vcg_const_Ball_lift hoare_vcg_all_lift
            hoare_vcg_imp_lift hoare_vcg_disj_lift valid_cte_at_neg_typ
          | simp add: cte_wp_at_neg2[where P="\<lambda>c. x \<in> obj_refs c" for x])+
  apply (clarsimp simp: o_def cte_wp_at_def)
  done

lemma sts_no_cap_asid[wp]:
  "\<lbrace>no_cap_to_obj_with_diff_ref cap S\<rbrace>
     set_thread_state t st
   \<lbrace>\<lambda>rv. no_cap_to_obj_with_diff_ref cap S\<rbrace>"
  by (simp add: no_cap_to_obj_with_diff_ref_def
                cte_wp_at_caps_of_state, wp)

lemma sts_mcpriority_tcb_at[wp]:
  "\<lbrace>mcpriority_tcb_at P t\<rbrace> set_thread_state p ts \<lbrace>\<lambda>rv. mcpriority_tcb_at P t\<rbrace>"
  apply (simp add: set_thread_state_def set_object_def)
  apply (wp | simp)+
  apply (clarsimp simp: pred_tcb_at_def obj_at_def)
  apply (drule get_tcb_SomeD)
  apply clarsimp
  done

lemma sts_mcpriority_tcb_at_ct[wp]:
  "\<lbrace>\<lambda>s. mcpriority_tcb_at P (cur_thread s) s\<rbrace> set_thread_state p ts \<lbrace>\<lambda>rv s. mcpriority_tcb_at P (cur_thread s) s\<rbrace>"
  apply (simp add: set_thread_state_def set_object_def set_thread_state_act_def set_scheduler_action_def)
  apply (wp is_schedulable_wp | simp)+
  apply (clarsimp simp: pred_tcb_at_def obj_at_def)
  apply (drule get_tcb_SomeD)
  apply clarsimp
  done

lemma option_None_True: "case_option (\<lambda>_. True) f x = (\<lambda>s. \<forall>y. x = Some y \<longrightarrow> f y s)"
  by (cases x; simp)

lemma option_None_True_const: "case_option True f x = (\<forall>y. x = Some y \<longrightarrow> f y)"
  by (cases x; simp)

lemma sts_tcb_inv_wf [wp]:
  "\<lbrace>tcb_inv_wf i\<rbrace> set_thread_state t st \<lbrace>\<lambda>rv. tcb_inv_wf i\<rbrace>"
  apply (case_tac i)
  by (wpsimp wp: set_thread_state_sc_at_pred_n set_thread_state_bound_sc_tcb_at
                 set_thread_state_valid_cap hoare_vcg_all_lift hoare_vcg_const_imp_lift
             simp: option_None_True option_None_True_const | wp sts_obj_at_impossible)+

lemma sts_valid_sched_context_inv[wp]:
  "\<lbrace>valid_sched_context_inv i\<rbrace> set_thread_state t st \<lbrace>\<lambda>rv. valid_sched_context_inv i\<rbrace>"
  by (cases i
      ; wpsimp split: cap.splits
      ; intro conjI
      ; wpsimp wp: sts_obj_at_impossible set_thread_state_bound_sc_tcb_at)

lemma sts_valid_cnode_inv[wp]:
  "\<lbrace>valid_cnode_inv i\<rbrace> set_thread_state t st \<lbrace>\<lambda>rv. valid_cnode_inv i\<rbrace>"
  by (cases i
      ; wpsimp wp: sts_nasty_bit[where ptr'="(p_a, p_b)" for p_a p_b, simplified]
                   hoare_vcg_const_imp_lift)

declare sts_arch_irq_control_inv_valid[wp]

lemma sts_irq_control_inv_valid[wp]:
  "\<lbrace>irq_control_inv_valid i\<rbrace> set_thread_state t st \<lbrace>\<lambda>rv. irq_control_inv_valid i\<rbrace>"
  by (cases i; wpsimp)

lemma sts_irq_handler_inv_valid[wp]:
  "\<lbrace>irq_handler_inv_valid i\<rbrace> set_thread_state t st \<lbrace>\<lambda>rv. irq_handler_inv_valid i\<rbrace>"
  by (cases i; wpsimp wp: hoare_vcg_ex_lift)

declare sts_valid_arch_inv[wp]

lemma sts_valid_inv[wp]:
  "\<lbrace>valid_invocation i\<rbrace> set_thread_state t st \<lbrace>\<lambda>rv. valid_invocation i\<rbrace>"
  by (cases i; wpsimp)


lemma sts_Restart_stay_simple:
  "\<lbrace>st_tcb_at simple t\<rbrace>
     set_thread_state t' Structures_A.Restart
   \<lbrace>\<lambda>rv. st_tcb_at simple t\<rbrace>"
  apply (rule hoare_pre)
   apply (wp sts_st_tcb_at_cases)
  apply simp
  done

lemma decode_inv_inv[wp]:
  notes if_split [split del]
  shows
  "\<lbrace>P\<rbrace> decode_invocation label args cap_index slot cap excaps \<lbrace>\<lambda>rv. P\<rbrace>"
  apply (case_tac cap, simp_all add: decode_invocation_def)
          apply (wp decode_tcb_inv_inv decode_domain_inv_inv
                    decode_sched_context_inv_inv decode_sched_control_inv_inv
                      | rule conjI | clarsimp
                      | simp split: bool.split)+
  done

lemma diminished_Untyped [simp]:
  "diminished (cap.UntypedCap d x xa idx) = (\<lambda>c. c = cap.UntypedCap d x xa idx)"
  apply (rule ext)
  apply (case_tac c,
         auto simp: diminished_def cap_rights_update_def mask_cap_def)
  done

lemma diminished_Reply [simp]: (* RT unnecessary? *)
  "diminished (cap.ReplyCap x) = (\<lambda>c. c = cap.ReplyCap x)"
  apply (rule ext)
  apply (case_tac c,
         auto simp: diminished_def cap_rights_update_def mask_cap_def)
  done

lemma diminished_IRQHandler [simp]:
  "diminished (cap.IRQHandlerCap irq) = (\<lambda>c. c = cap.IRQHandlerCap irq)"
  apply (rule ext)
  apply (case_tac c,
         auto simp: diminished_def cap_rights_update_def mask_cap_def)
  done

lemma cnode_diminished_strg:
  "(\<exists>ptr. cte_wp_at (diminished cap) ptr s)
    \<longrightarrow> (is_cnode_cap cap \<longrightarrow> (\<forall>ref \<in> cte_refs cap (interrupt_irq_node s).
                                    ex_cte_cap_wp_to is_cnode_cap ref s))"
  apply (clarsimp simp: ex_cte_cap_wp_to_def)
  apply (intro exI, erule cte_wp_at_weakenE)
  apply (clarsimp simp: diminished_def)
  done


lemma invs_valid_arch_caps[elim!]:
  "invs s \<Longrightarrow> valid_arch_caps s"
  by (clarsimp simp: invs_def valid_state_def)

context Syscall_AI begin

lemma decode_inv_wf[wp]:
  "\<lbrace>valid_cap cap and invs and cte_wp_at (diminished cap) slot
           and ex_cte_cap_to slot
           and (\<lambda>s::det_ext state. \<forall>r\<in>zobj_refs cap. ex_nonz_cap_to r s)
           and (\<lambda>s. \<forall>r\<in>cte_refs cap (interrupt_irq_node s). ex_cte_cap_to r s)
           and (\<lambda>s. \<forall>cap \<in> set excaps. \<forall>r\<in>cte_refs (fst cap) (interrupt_irq_node s). ex_cte_cap_to r s)
           and (\<lambda>s. \<forall>x \<in> set excaps. s \<turnstile> (fst x))
           and (\<lambda>s. \<forall>x \<in> set excaps. \<forall>r\<in>zobj_refs (fst x). ex_nonz_cap_to r s)
           and (\<lambda>s. \<forall>x \<in> set excaps. cte_wp_at (diminished (fst x)) (snd x) s)
           and (\<lambda>s. \<forall>x \<in> set excaps. real_cte_at (snd x) s)
           and (\<lambda>s. \<forall>x \<in> set excaps. ex_cte_cap_wp_to is_cnode_cap (snd x) s)
           and (\<lambda>s. \<forall>x \<in> set excaps. cte_wp_at (interrupt_derived (fst x)) (snd x) s)\<rbrace>
     decode_invocation label args cap_index slot cap excaps
   \<lbrace>valid_invocation\<rbrace>,-"
  apply (simp add: decode_invocation_def
             cong: cap.case_cong if_cong
                split del: if_split)
  apply (rule hoare_pre)
   apply (wp Tcb_AI.decode_tcb_inv_wf decode_domain_inv_wf[simplified split_def]
             decode_sched_context_inv_wf decode_sched_control_inv_wf | wpc |
          simp add: o_def uncurry_def split_def del: is_cnode_cap.simps cte_refs.simps)+
  apply (strengthen cnode_diminished_strg)
  apply (clarsimp simp: valid_cap_def cte_wp_at_eq_simp is_cap_simps
             cap_rights_update_def ex_cte_cap_wp_to_weakenE[OF _ TrueI]
             cte_wp_at_caps_of_state
           split: cap.splits)
       apply (thin_tac " \<forall>x\<in>set excaps. P x \<and> Q x" for P Q)+
       apply (drule (1) bspec)+
       apply (subst split_paired_Ex[symmetric], rule exI, simp)
      apply (thin_tac " \<forall>x\<in>set excaps. P x \<and> Q x" for P Q)+
      apply (rule conjI)
       apply (subst split_paired_Ex[symmetric], rule_tac x=slot in exI, simp)
      apply clarsimp
      apply (drule (1) bspec)+
      apply (subst split_paired_Ex[symmetric], rule exI, simp)
     apply (thin_tac " \<forall>x\<in>set excaps. P x \<and> Q x" for P Q)+
     apply (drule (1) bspec)+
     apply (clarsimp simp add: ex_cte_cap_wp_to_weakenE[OF _ TrueI])
(*     apply (rule diminished_no_cap_to_obj_with_diff_ref)
      apply (fastforce simp add: cte_wp_at_caps_of_state)
     apply (simp add: invs_valid_arch_caps)
    apply (simp add: invs_valid_objs invs_valid_global_refs)
   apply (thin_tac " \<forall>x\<in>set excaps. P x \<and> Q x" for P Q)+
   apply (rule conjI)
    apply clarsimp
    apply (drule (1) bspec)+
    apply (subst split_paired_Ex[symmetric], rule exI, simp)
   apply (clarsimp simp add: diminished_def mask_cap_def cap_rights_update_def
                   split: cap.splits)
  apply (thin_tac " \<forall>x\<in>set excaps. P x \<and> Q x" for P Q)+
  apply (subst split_paired_Ex[symmetric], rule exI, simp)
  done*) sorry

end

lemma lcs_valid [wp]:
  "\<lbrace>invs\<rbrace> lookup_cap_and_slot t xs \<lbrace>\<lambda>x s. s \<turnstile> fst x\<rbrace>, -"
  unfolding lookup_cap_and_slot_def
  apply (rule hoare_pre)
   apply (wp|clarsimp simp: split_def)+
  done

lemma lec_valid_cap [wp]:
  "\<lbrace>invs\<rbrace> lookup_extra_caps t xa mi \<lbrace>\<lambda>rv s. (\<forall>x\<in>set rv. s \<turnstile> fst x)\<rbrace>, -"
  unfolding lookup_extra_caps_def
  by (wpsimp wp: mapME_set)

lemma lcs_ex_cap_to [wp]:
  "\<lbrace>invs\<rbrace> lookup_cap_and_slot t xs \<lbrace>\<lambda>x s. \<forall>r\<in>cte_refs (fst x) (interrupt_irq_node s). ex_cte_cap_to r s\<rbrace>, -"
  unfolding lookup_cap_and_slot_def by wpsimp

lemma lcs_ex_nonz_cap_to [wp]:
  "\<lbrace>invs\<rbrace> lookup_cap_and_slot t xs \<lbrace>\<lambda>x s. \<forall>r\<in>zobj_refs (fst x). ex_nonz_cap_to r s\<rbrace>, -"
  unfolding lookup_cap_and_slot_def by wpsimp

lemma lcs_cte_at[wp]:
  "\<lbrace>valid_objs\<rbrace> lookup_cap_and_slot t xs \<lbrace>\<lambda>rv. cte_at (snd rv)\<rbrace>,-"
  apply (simp add: lookup_cap_and_slot_def split_def)
  apply (wp | simp)+
  done

lemma lec_ex_cap_to [wp]:
  "\<lbrace>invs\<rbrace>
  lookup_extra_caps t xa mi
  \<lbrace>\<lambda>rv s. (\<forall>cap \<in> set rv. \<forall>r\<in>cte_refs (fst cap) (interrupt_irq_node s). ex_cte_cap_to r s)\<rbrace>, -"
  unfolding lookup_extra_caps_def
  by (wp mapME_set | simp)+

lemma lec_ex_nonz_cap_to [wp]:
  "\<lbrace>invs\<rbrace>
  lookup_extra_caps t xa mi
  \<lbrace>\<lambda>rv s. (\<forall>cap \<in> set rv. \<forall>r\<in>zobj_refs (fst cap). ex_nonz_cap_to r s)\<rbrace>, -"
  unfolding lookup_extra_caps_def
  by (wp mapME_set | simp)+

lemma lookup_extras_real_ctes[wp]:
  "\<lbrace>valid_objs\<rbrace> lookup_extra_caps t xs info \<lbrace>\<lambda>rv s. \<forall>x \<in> set rv. real_cte_at (snd x) s\<rbrace>,-"
  apply (simp add: lookup_extra_caps_def
              split del: if_split)
  apply (rule hoare_pre)
   apply (wp mapME_set)
      apply (simp add: lookup_cap_and_slot_def split_def)
      apply (wp case_options_weak_wp mapM_wp'
                 | simp add: load_word_offs_word_def)+
  done

lemma lookup_extras_ctes[wp]:
  "\<lbrace>valid_objs\<rbrace> lookup_extra_caps t xs info \<lbrace>\<lambda>rv s. \<forall>x \<in> set rv. cte_at (snd x) s\<rbrace>,-"
  apply (rule hoare_post_imp_R)
   apply (rule lookup_extras_real_ctes)
  apply (simp add: real_cte_at_cte)
  done

lemma lsft_ex_cte_cap_to:
  "\<lbrace>invs and K (\<forall>cap. is_cnode_cap cap \<longrightarrow> P cap)\<rbrace>
     lookup_slot_for_thread t cref
   \<lbrace>\<lambda>rv s. ex_cte_cap_wp_to P (fst rv) s\<rbrace>,-"
  apply (simp add: lookup_slot_for_thread_def)
  apply (wp rab_cte_cap_to)
  apply (clarsimp simp: ex_cte_cap_wp_to_def)
  apply (clarsimp dest!: get_tcb_SomeD)
  apply (frule cte_wp_at_tcbI[where t="(t', tcb_cnode_index 0)" and P="(=) v" for t' v, simplified])
    apply fastforce
   apply fastforce
  apply (intro exI, erule cte_wp_at_weakenE)
  apply clarsimp
  done

(* FIXME: move / generalize lemma in GenericLib *)
lemma mapME_wp:
  assumes x: "\<And>x. x \<in> S \<Longrightarrow> \<lbrace>P\<rbrace> f x \<lbrace>\<lambda>_. P\<rbrace>, \<lbrace>E\<rbrace>"
  shows      "set xs \<subseteq> S \<Longrightarrow> \<lbrace>P\<rbrace> mapME f xs \<lbrace>\<lambda>_. P\<rbrace>, \<lbrace>E\<rbrace>"
  apply (induct xs)
   apply (simp add: mapME_def sequenceE_def)
   apply wp
  apply (simp add: mapME_Cons)
  apply (wpsimp wp: x|assumption)+
  done

lemmas mapME_wp' = mapME_wp [OF _ subset_refl]

(* FIXME: move to CSpace_R *)
lemma resolve_address_bits_valid_fault:
  "\<lbrace> valid_objs and valid_cap (fst param)\<rbrace>
   resolve_address_bits param
   \<lbrace>\<lambda>_. valid_objs\<rbrace>,
   \<lbrace>\<lambda>f s. valid_fault (ExceptionTypes_A.fault.CapFault x y f)\<rbrace>"
unfolding resolve_address_bits_def
proof (induct param rule: resolve_address_bits'.induct)
  case (1 cap cref)
  show ?case
    apply (clarsimp simp: validE_R_def validE_def valid_def  split: sum.split)
    apply (subst (asm) resolve_address_bits'.simps)
    apply (split cap.splits)
              defer 6 (* cnode *)
              apply (simp_all add: spec_validE_def validE_def valid_def
                         throwError_def return_def valid_fault_def)[13]
    apply (simp only: split: cap.splits if_split_asm)
     apply (simp add: fail_def)
    apply (simp only: K_bind_def in_bindE)
    apply (elim conjE exE disjE)
        apply ((clarsimp simp: whenE_def bindE_def bind_def lift_def liftE_def
                    throwError_def returnOk_def return_def valid_fault_def
                    valid_cap_def2 wellformed_cap_def word_bits_def
                  split: if_split_asm cap.splits)+)[4]
    apply (split if_split_asm)
     apply (clarsimp simp: whenE_def bindE_def bind_def lift_def liftE_def
                throwError_def returnOk_def return_def valid_fault_def
                valid_cap_def2 wellformed_cap_def
              split: if_split_asm cap.splits)
    apply (simp only: K_bind_def in_bindE)
    apply (elim conjE exE disjE)
     apply (clarsimp simp: whenE_def bindE_def bind_def lift_def liftE_def
                throwError_def returnOk_def return_def valid_fault_def
                valid_cap_def2 wellformed_cap_def
              split: if_split_asm cap.splits)
    apply (split if_split_asm)
     apply (frule (8) "1.hyps")
     apply (clarsimp simp add: validE_def valid_def whenE_def bindE_def
               bind_def lift_def liftE_def throwError_def
               returnOk_def return_def valid_fault_def
             split: if_split_asm cap.splits sum.splits)
     apply (frule in_inv_by_hoareD [OF get_cap_inv])
     apply simp
     apply (frule (1) post_by_hoare [OF get_cap_valid])
     apply (erule_tac x=s in allE, erule impE, simp)
     apply (drule (1) bspec, clarsimp)
    apply (clarsimp simp add: returnOk_def return_def)
    apply (frule in_inv_by_hoareD [OF get_cap_inv])
    apply (clarsimp simp: whenE_def bindE_def bind_def throwError_def
                          returnOk_def return_def
                    split: if_split_asm cap.splits sum.splits)
    done
qed

lemma resolve_address_bits_valid_fault2:
  "\<lbrace>invs and valid_cap (fst param)\<rbrace>
   resolve_address_bits param
   -,\<lbrace>\<lambda>f s. valid_fault (ExceptionTypes_A.fault.CapFault x y f)\<rbrace>"
  apply (cut_tac resolve_address_bits_valid_fault[of param x y])
  apply (clarsimp simp add: validE_E_def validE_def valid_def
                  split: sum.splits)
  apply (drule invs_valid_objs)
  apply fastforce
  done

lemma lookup_cap_and_slot_valid_fault:
  "\<lbrace>valid_objs\<rbrace> lookup_cap_and_slot thread cptr
   \<lbrace>\<lambda>_. valid_objs\<rbrace>,
   \<lbrace>\<lambda>ft s. valid_fault (ExceptionTypes_A.CapFault (of_bl cptr) rp ft)\<rbrace>"
  apply (simp add: lookup_cap_and_slot_def split_def lookup_slot_for_thread_def
         | wp resolve_address_bits_valid_fault)+
  apply (clarsimp simp: objs_valid_tcb_ctable)
  done

lemma lookup_cap_and_slot_valid_fault2[wp]:
  "\<lbrace>invs\<rbrace> lookup_cap_and_slot thread (to_bl p)
   -,\<lbrace>\<lambda>ft s. valid_fault (ExceptionTypes_A.CapFault p rp ft)\<rbrace>"
  using lookup_cap_and_slot_valid_fault[of thread "to_bl p"]
  apply (clarsimp simp add: validE_E_def validE_def valid_def
                  split: sum.splits)
  apply (drule invs_valid_objs)
  apply fastforce
  done

lemma lec_valid_fault:
  "\<lbrace>valid_objs\<rbrace>
   lookup_extra_caps thread buffer info
   \<lbrace>\<lambda>_. valid_objs\<rbrace>,\<lbrace>\<lambda>rv s. valid_fault rv\<rbrace>"
  apply (simp add: lookup_extra_caps_def split del: if_split)
  apply (wp mapME_wp' lookup_cap_and_slot_valid_fault)
  done

lemma lec_valid_fault2[wp]:
  "\<lbrace>invs\<rbrace> lookup_extra_caps thread buffer info -,\<lbrace>\<lambda>rv s. valid_fault rv\<rbrace>"
  apply (cut_tac lec_valid_fault[of thread buffer info])
  apply (clarsimp simp add: validE_E_def validE_def valid_def
                  split: sum.splits )
  apply (drule invs_valid_objs)
  apply fastforce
  done

lemma lec_caps_to[wp]:
  "\<lbrace>invs and K (\<forall>cap. is_cnode_cap cap \<longrightarrow> P cap)\<rbrace> lookup_extra_caps t buffer info
   \<lbrace>\<lambda>rv s. (\<forall>x\<in>set rv. ex_cte_cap_wp_to P (snd x) s)\<rbrace>,-"
  apply (simp add: lookup_extra_caps_def split del: if_split)
  apply (rule hoare_pre)
   apply (wp mapME_set)
      apply (simp add: lookup_cap_and_slot_def split_def)
      apply (wp lsft_ex_cte_cap_to mapM_wp'
                    | simp add: load_word_offs_word_def | wpc)+
  done

lemma get_cap_int_derived[wp]:
  "\<lbrace>\<top>\<rbrace> get_cap slot \<lbrace>\<lambda>rv. cte_wp_at (interrupt_derived rv) slot\<rbrace>"
  apply (wp get_cap_wp)
  apply (clarsimp simp: cte_wp_at_caps_of_state interrupt_derived_def)
  done

lemma lec_derived[wp]:
  "\<lbrace>invs\<rbrace>
     lookup_extra_caps t buffer info
   \<lbrace>\<lambda>rv s. (\<forall>x\<in>set rv. cte_wp_at (interrupt_derived (fst x)) (snd x) s)\<rbrace>,-"
  apply (simp add: lookup_extra_caps_def split del: if_split)
  apply (rule hoare_pre)
   apply (wp mapME_set)
      apply (simp add: lookup_cap_and_slot_def split_def)
      apply (wp | simp)+
  done

lemma lookup_cap_and_slot_dimished [wp]:
  "\<lbrace>valid_objs\<rbrace>
    lookup_cap_and_slot thread cptr
   \<lbrace>\<lambda>x. cte_wp_at (diminished (fst x)) (snd x)\<rbrace>, -"
  apply (simp add: lookup_cap_and_slot_def split_def)
  apply (wp get_cap_wp)
   apply (rule hoare_post_imp_R [where Q'="\<lambda>_. valid_objs"])
    apply wp
   apply simp
   apply (clarsimp simp: cte_wp_at_caps_of_state diminished_def)
   apply (rule exI, rule cap_mask_UNIV[symmetric])
   apply (drule (1) caps_of_state_valid_cap, simp add: valid_cap_def2)
  apply simp
  done

lemma lookup_extra_caps_diminished [wp]:
  "\<lbrace>valid_objs\<rbrace> lookup_extra_caps thread xb info
  \<lbrace>\<lambda>rv s. (\<forall>x\<in>set rv. cte_wp_at (diminished (fst x)) (snd x) s)\<rbrace>,-"
  apply (simp add: lookup_extra_caps_def)
  apply (wp mapME_set|simp)+
  done


(*FIXME: move to NonDetMonadVCG.valid_validE_R *)
lemma valid_validE_R_gen:
  "\<lbrakk>\<And>rv s. Q' (Inr rv) s \<Longrightarrow> Q rv s; \<lbrace>P\<rbrace> f \<lbrace>Q'\<rbrace>\<rbrakk> \<Longrightarrow> \<lbrace>P\<rbrace> f \<lbrace>Q\<rbrace>, -"
  by (fastforce simp: validE_R_def validE_def valid_def split_def)

lemma valid_validE_R_eq:
  "\<lbrakk>Q = Q'\<circ>Inr; \<lbrace>P\<rbrace> f \<lbrace>Q'\<rbrace>\<rbrakk> \<Longrightarrow> \<lbrace>P\<rbrace> f \<lbrace>Q\<rbrace>, -"
  by (fastforce simp: validE_R_def validE_def valid_def split_def)


crunch tcb_at[wp]: reply_from_kernel "tcb_at t"
  (simp: crunch_simps)

crunch pred_tcb_at[wp]: reply_from_kernel "pred_tcb_at proj P t"
  (simp: crunch_simps)

crunch cap_to[wp]: reply_from_kernel "ex_nonz_cap_to p"
  (simp: crunch_simps)

crunch it[wp]: reply_from_kernel "\<lambda>s. P (idle_thread s)"
  (simp: crunch_simps)

crunch cte_wp_at[wp]: reply_from_kernel "cte_wp_at P p"
  (simp: crunch_simps)


lemma ts_Restart_case_helper:
  "(case ts of Structures_A.Restart \<Rightarrow> A | _ \<Rightarrow> B)
 = (if ts = Structures_A.Restart then A else B)"
  by (case_tac ts, simp_all)


lemma lcs_ex_cap_to2[wp]:
  "\<lbrace>invs and K (\<forall>cap. is_cnode_cap cap \<longrightarrow> P cap)\<rbrace>
      lookup_cap_and_slot t cref \<lbrace>\<lambda>rv. ex_cte_cap_wp_to P (snd rv)\<rbrace>,-"
  apply (rule hoare_pre)
   apply (simp add: lookup_cap_and_slot_def split_def)
   apply (wp lsft_ex_cte_cap_to | simp)+
  done

lemma hoare_vcg_const_imp_lift_E[wp]:
  "\<lbrace>P\<rbrace> f -, \<lbrace>Q\<rbrace> \<Longrightarrow> \<lbrace>\<lambda>s. F \<longrightarrow> P s\<rbrace> f -, \<lbrace>\<lambda>rv s. F \<longrightarrow> Q rv s\<rbrace>"
  apply (cases F) apply auto
  apply wp
  done

context Syscall_AI begin

lemma hinv_invs':
  fixes Q :: "det_ext state \<Rightarrow> bool" and calling blocking
  assumes perform_invocation_Q[wp]:
    "\<And>block class can_donate i.
      \<lbrace>invs and Q and ct_active and valid_invocation i\<rbrace>
        perform_invocation block class can_donate i
      \<lbrace>\<lambda>_.Q\<rbrace>"
  assumes handle_fault_Q[wp]:
    "\<And>t f.
      \<lbrace>invs and Q and st_tcb_at active t and ex_nonz_cap_to t and (\<lambda>_. valid_fault f)\<rbrace>
        handle_fault t f
      \<lbrace>\<lambda>r. Q\<rbrace>"
  assumes reply_from_kernel_Q[wp]:
    "\<And>a b. \<lbrace>invs and Q\<rbrace> reply_from_kernel a b \<lbrace>\<lambda>_.Q\<rbrace>"
  assumes sts_Q[wp]:
    "\<And>a b. \<lbrace>invs and Q\<rbrace> set_thread_state a b \<lbrace>\<lambda>_.Q\<rbrace>"
  shows
    "\<lbrace>invs and Q and ct_active\<rbrace> handle_invocation calling blocking can_donate cptr \<lbrace>\<lambda>rv s. invs s \<and> Q s\<rbrace>"
  apply (simp add: handle_invocation_def ts_Restart_case_helper split_def
                   liftE_liftM_liftME liftME_def bindE_assoc)

  apply (wp syscall_valid sts_invs_minor2 rfk_invs
            hoare_vcg_all_lift hoare_vcg_disj_lift | simp split del: if_split)+
  apply (rule_tac Q = "\<lambda>st. st_tcb_at ((=) st) thread and (invs and Q)" in
         hoare_post_imp)
  apply (auto elim!: pred_tcb_weakenE st_tcb_ex_cap
              dest: st_tcb_at_idle_thread
              simp: st_tcb_at_tcb_at)[1]
  apply (rule gts_sp)
(*  apply wp
  apply (simp add: ct_in_state_def conj_commute conj_left_commute)
  apply wp
  apply (rule_tac Q = "\<lambda>rv s. st_tcb_at active thread s \<and> cur_thread s = thread" in
         hoare_post_imp)
  apply simp
  apply (wp sts_st_tcb_at')
  apply (simp only: simp_thms K_def if_apply_def2)
  apply (rule hoare_vcg_E_elim)
  apply (wp | simp add: if_apply_def2)+
  apply (auto simp: ct_in_state_def elim: st_tcb_ex_cap)
  done*) sorry

lemmas hinv_invs[wp] = hinv_invs'
  [where Q=\<top>,simplified hoare_post_taut, OF TrueI TrueI TrueI TrueI,simplified]

(* FIXME: move *)
lemma hinv_tcb[wp]:
  "\<And>t calling blocking can_donate cptr.
    \<lbrace>st_tcb_at active t and invs and ct_active\<rbrace>
      handle_invocation calling blocking can_donate cptr
    \<lbrace>\<lambda>rv. tcb_at t :: det_ext state \<Rightarrow> bool\<rbrace>"
  apply (simp add: handle_invocation_def split_def
                   ts_Restart_case_helper
                   liftE_liftM_liftME liftME_def bindE_assoc)
  apply (wp syscall_valid sts_st_tcb_at_cases
            ct_in_state_set lec_caps_to
            | simp)+
  apply (clarsimp simp: st_tcb_at_tcb_at invs_valid_objs
                        ct_in_state_def)
  apply (fastforce elim!: st_tcb_ex_cap)
  done

lemma get_cap_reg_inv[wp]: "\<lbrace>P\<rbrace> get_cap_reg r \<lbrace>\<lambda>_. P\<rbrace>"
  by (wpsimp simp: get_cap_reg_def)

lemma hs_tcb_on_err:
  "\<lbrace>st_tcb_at active t and invs and ct_active\<rbrace>
     handle_send blocking
   -,\<lbrace>\<lambda>e. tcb_at t :: det_ext state \<Rightarrow> bool\<rbrace>"
  apply (unfold handle_send_def whenE_def fun_app_def)
  apply (wpsimp | rule hoare_strengthen_post [OF hinv_tcb])+
  done

lemma hs_invs[wp]: "\<lbrace>invs and ct_active\<rbrace> handle_send blocking \<lbrace>\<lambda>r. invs :: det_ext state \<Rightarrow> bool\<rbrace>"
  apply (rule validE_valid)
  apply (simp add: handle_send_def whenE_def)
  apply (wp | simp add: ct_in_state_def tcb_at_invs)+
  done

end

(*
lemma tcb_cnode_index_3_reply_or_null:
  "\<lbrakk> tcb_at t s; tcb_cap_valid cap (t, tcb_cnode_index 3) s \<rbrakk> \<Longrightarrow> is_reply_cap cap \<or> cap = cap.NullCap"
  apply (clarsimp  simp: tcb_cap_valid_def st_tcb_def2 tcb_at_def)
  apply (clarsimp split: Structures_A.thread_state.split_asm)
  done*)

lemma ex_nonz_cap_to_tcb_strg:
  "(\<exists>cref. cte_wp_at (\<lambda>cap. is_thread_cap cap \<and> p \<in> zobj_refs cap) cref s)
       \<longrightarrow> ex_nonz_cap_to p s"
  by (fastforce simp: ex_nonz_cap_to_def cte_wp_at_caps_of_state)

lemma ex_tcb_cap_to_tcb_at_strg:
  "ex_nonz_cap_to p s \<and> tcb_at p s \<and> valid_objs s \<longrightarrow>
   (\<exists>cref. cte_wp_at (\<lambda>cap. is_thread_cap cap \<and> p \<in> zobj_refs cap) cref s)"
  apply (clarsimp simp: ex_nonz_cap_to_def cte_wp_at_caps_of_state
                        zobj_refs_to_obj_refs)
  apply (drule(1) caps_of_state_valid_cap[rotated])
  apply (drule(2) valid_cap_tcb_at_tcb_or_zomb)
  apply fastforce
  done
(*
lemma delete_caller_cap_nonz_cap:
  "\<lbrace>ex_nonz_cap_to p and tcb_at t and valid_objs\<rbrace>
      delete_caller_cap t
   \<lbrace>\<lambda>rv. ex_nonz_cap_to p\<rbrace>"
  apply (simp add: delete_caller_cap_def ex_nonz_cap_to_def cte_wp_at_caps_of_state)
  apply (rule hoare_pre)
  apply (wp hoare_vcg_ex_lift cap_delete_one_caps_of_state)
  apply (clarsimp simp: cte_wp_at_caps_of_state)
  apply (rule_tac x=a in exI)
  apply (rule_tac x=b in exI)
  apply clarsimp
  apply (drule (1) tcb_cap_valid_caps_of_stateD)
  apply (drule (1) tcb_cnode_index_3_reply_or_null)
  apply (auto simp: is_cap_simps)
  done

lemma delete_caller_cap_invs[wp]:
  "\<lbrace>invs and tcb_at t\<rbrace> delete_caller_cap t \<lbrace>\<lambda>rv. invs\<rbrace>"
  apply (simp add: delete_caller_cap_def, wp)
  apply (clarsimp simp: emptyable_def)
  done

lemma delete_caller_cap_simple[wp]:
  "\<lbrace>st_tcb_at active t\<rbrace> delete_caller_cap t' \<lbrace>\<lambda>rv. st_tcb_at active t\<rbrace>"
  apply (simp add: delete_caller_cap_def)
  apply (wp cap_delete_one_st_tcb_at)
  apply simp
  done

lemma delete_caller_deletes_caller[wp]:
  "\<lbrace>\<top>\<rbrace> delete_caller_cap t \<lbrace>\<lambda>rv. cte_wp_at ((=) cap.NullCap) (t, tcb_cnode_index 3)\<rbrace>"
  apply (rule_tac Q="\<lambda>rv. cte_wp_at (\<lambda>c. c = cap.NullCap) (t, tcb_cnode_index 3)"
               in hoare_post_imp,
         clarsimp elim!: cte_wp_at_weakenE)
  apply (simp add: delete_caller_cap_def cap_delete_one_def unless_def, wp)
   apply (simp add: if_apply_def2, wp get_cap_wp)
  apply (clarsimp elim!: cte_wp_at_weakenE)
  done

lemma delete_caller_cap_deleted[wp]:
  "\<lbrace>\<top>\<rbrace> delete_caller_cap thread \<lbrace>\<lambda>rv. cte_wp_at (\<lambda>c. c = cap.NullCap) (thread, tcb_cnode_index 3)\<rbrace>"
  by (simp add: delete_caller_cap_def, wp)*)

lemma invs_valid_tcb_ctable_strengthen:
  "invs s \<longrightarrow> ((\<exists>y. get_tcb thread s = Some y) \<longrightarrow>
               invs s \<and> s \<turnstile> tcb_ctable (the (get_tcb thread s)))"
  by (clarsimp simp: invs_valid_tcb_ctable)

lemma hw_invs[wp]: "\<lbrace>invs and ct_active\<rbrace> handle_recv is_blocking can_reply \<lbrace>\<lambda>r. invs\<rbrace>"
  apply (simp add: handle_recv_def Let_def ep_ntfn_cap_case_helper split del: if_split
    cong: if_cong)
  apply (wpsimp wp: get_simple_ko_wp)
(*  apply (wp get_simple_ko_wp hoare_vcg_ball_lift | simp)+
     apply (rule hoare_vcg_E_elim)
      apply (simp add: lookup_cap_def lookup_slot_for_thread_def)
      apply wp
       apply (simp add: split_def)
       apply (wp resolve_address_bits_valid_fault2)+
     apply (simp add: valid_fault_def)
     apply ((wp hoare_vcg_all_lift_R lookup_cap_ex_cap
          | simp add: obj_at_def
          | simp add: conj_disj_distribL ball_conj_distrib
          | wp_once hoare_drop_imps)+)
  apply (simp add: ct_in_state_def)
  apply (fold obj_at_def)
  apply (fastforce elim!: invs_valid_tcb_ctable st_tcb_ex_cap)
  done*) sorry

crunch tcb_at[wp]: lookup_reply, handle_recv "tcb_at t"
  (wp: crunch_wps simp: crunch_simps)

lemma sts_st_tcb_at'':
  "\<lbrace>K (t = t' \<and> P st)\<rbrace> set_thread_state t st \<lbrace>\<lambda>rv. st_tcb_at P t'\<rbrace>"
  apply (cases "t = t'")
   apply (simp only: simp_thms)
   apply (rule sts_st_tcb_at')
  apply simp
  done

lemma null_cap_on_failure_wp[wp]:
  assumes x: "\<lbrace>P\<rbrace> f \<lbrace>Q\<rbrace>,\<lbrace>\<lambda>rv. Q cap.NullCap\<rbrace>"
  shows      "\<lbrace>P\<rbrace> null_cap_on_failure f \<lbrace>Q\<rbrace>"
  unfolding ncof_is_a_catch
  by (wp x)

crunch_ignore (add:null_cap_on_failure)

declare hoare_seq_ext[wp] hoare_vcg_precond_imp [wp_comb]

lemma ct_active_simple [elim!]:
  "ct_active s \<Longrightarrow> st_tcb_at simple (cur_thread s) s"
  by (fastforce simp: ct_in_state_def elim!: pred_tcb_weakenE)

lemma active_from_running:
  "ct_running  s  \<Longrightarrow> ct_active  s"
  by (clarsimp elim!: pred_tcb_weakenE
               simp: ct_in_state_def)+

(*
lemma tcb_caller_cap:
  "\<lbrakk>tcb_at t s; valid_objs s\<rbrakk> \<Longrightarrow>
   cte_wp_at (is_reply_cap or (=) cap.NullCap) (t, tcb_cnode_index 3) s"
  by (fastforce intro: tcb_cap_wp_at split: Structures_A.thread_state.split_asm)
*)

crunch cur_thread[wp]: set_extra_badge "\<lambda>s. P (cur_thread s)"

lemmas cap_delete_one_st_tcb_at_simple[wp] =
    cap_delete_one_st_tcb_at[where P=simple, simplified]

lemma simple_if_Restart_Inactive:
  "simple (if P then Structures_A.Restart else Structures_A.Inactive)"
  by simp

crunch (in Syscall_AI) vo[wp]: handle_fault_reply "valid_objs :: 'state_ext state \<Rightarrow> _"

lemmas handle_fault_reply_typ_ats[wp] =
    abs_typ_at_lifts [OF handle_fault_reply_typ_at]

lemma tcb_state_If_valid[simp]:
  "valid_tcb_state (if P then Structures_A.Restart else Structures_A.Inactive)
      = \<top>"
  by (rule ext, simp add: valid_tcb_state_def)

lemma drop_when_dxo_wp: "(\<And>f s. P (trans_state f s) = P s ) \<Longrightarrow> \<lbrace>P\<rbrace> when b (do_extended_op e) \<lbrace>\<lambda>_.P\<rbrace>"
  apply (clarsimp simp add: when_def)
  apply (wp | simp)+
  done

context Syscall_AI begin

crunch ex_nonz_cap_to[wp]: handle_timeout "ex_nonz_cap_to p"
(wp: crunch_wps thread_set_cap_to simp: crunch_simps ran_tcb_cap_cases)

lemma do_reply_transfer_nonz_cap:
  "\<lbrace>\<lambda>s :: 'state_ext state. ex_nonz_cap_to p s\<rbrace>
     do_reply_transfer sender reply
   \<lbrace>\<lambda>rv. ex_nonz_cap_to p\<rbrace>"
  apply (simp add: do_reply_transfer_def)
  by (wpsimp wp: hoare_drop_imps hoare_vcg_all_lift get_tcb_obj_ref_wp
                 thread_set_cap_to
           simp: ran_tcb_cap_cases
      | rule conjI)+

lemma hc_invs[wp]:
  "\<lbrace>invs and ct_active\<rbrace> handle_call \<lbrace>\<lambda>rv. invs :: det_ext state \<Rightarrow> bool\<rbrace>"
  by (simp add: handle_call_def) wpsimp

end
(* FIXME: move *) (* FIXME: should we add this to the simpset? *)
lemma select_insert:
  "select (insert x X) = (return x \<sqinter> select X)"
  by (simp add: alternative_def select_def return_def)


context Syscall_AI begin

lemma he_invs[wp]:
  "\<And>e.
    \<lbrace>\<lambda>s. invs s \<and> (e \<noteq> Interrupt \<longrightarrow> ct_active s)\<rbrace>
      handle_event e
    \<lbrace>\<lambda>rv. invs :: 'state_ext state \<Rightarrow> bool\<rbrace>"
  apply (case_tac e, simp_all)
      apply (rename_tac syscall)
      apply (case_tac syscall, simp_all)
  sorry (*
      apply (((rule hoare_pre, wp hvmf_active) |
                 wpc | wp hoare_drop_imps hoare_vcg_all_lift |
                 simp add: if_apply_def2 |
                 fastforce simp: tcb_at_invs ct_in_state_def valid_fault_def
                         elim!: st_tcb_ex_cap)+)
 *)

end

(* Lemmas related to preservation of runnability over handle_recv for woken threads
   these are presently unused, but have proven useful in the past *)
context notes if_cong[cong] begin

lemma complete_signal_state_refs_of:
  "\<lbrace>\<lambda>s. P (state_refs_of s) \<rbrace> complete_signal ntfnc t \<lbrace>\<lambda>rv s. P (state_refs_of s) \<rbrace>"
  unfolding complete_signal_def
  apply (rule hoare_pre)
   apply (wp get_simple_ko_wp | wpc | simp)+
  apply clarsimp
  apply (subgoal_tac " get_refs NTFNBound (ntfn_bound_tcb ntfn) \<union>
                       get_refs NTFNSchedContext (ntfn_sc ntfn) = state_refs_of s ntfnc")
   apply (clarsimp simp: if_apply_def2 split: if_splits if_split_asm)
   subgoal by (subst eq_commute, auto cong: if_cong)
  apply (clarsimp simp: state_refs_of_def obj_at_def)
  done

lemma do_nbrecv_failed_transfer_state_refs_of[wp]:
  "\<lbrace>\<lambda>s. P (state_refs_of s) \<rbrace> do_nbrecv_failed_transfer t \<lbrace>\<lambda>rv s. P (state_refs_of s) \<rbrace>"
  unfolding do_nbrecv_failed_transfer_def
  apply (rule hoare_pre)
   apply (wp get_simple_ko_wp | wpc | simp)+
  done

lemma fast_finalise_sym_refs:
  "\<lbrace>invs\<rbrace> fast_finalise cap final \<lbrace>\<lambda>y s. sym_refs (state_refs_of s)\<rbrace>"
  apply (cases cap;
         (solves \<open>simp\<close>)?)
      apply (wp cancel_all_signals_invs cancel_all_ipc_invs unbind_maybe_notification_invs
                cancel_ipc_invs sched_context_unbind_yield_from_invs get_simple_ko_wp
             | strengthen invs_sym_refs
             | clarsimp)+
  done

crunch state_refs_of[wp]: empty_slot "\<lambda>s. P (state_refs_of s)"
  (wp: crunch_wps simp: crunch_simps interrupt_update.state_refs_update)

lemmas sts_st_tcb_at_other = sts_st_tcb_at_neq[where proj=itcb_state]

lemma reply_unlink_runnable[wp]:
  "\<lbrace>st_tcb_at runnable t\<rbrace> reply_unlink_tcb rptr \<lbrace>\<lambda>rv. st_tcb_at runnable t\<rbrace>"
  apply (simp add: reply_unlink_tcb_def)
  apply (rule hoare_seq_ext[OF _ get_simple_ko_sp])
  apply (case_tac "reply_tcb reply"; clarsimp simp: assert_opt_def)
  apply (case_tac "a=t", clarsimp)
   defer
   apply (wpsimp wp: sts_st_tcb_at_cases assert_inv)
  apply (rule hoare_seq_ext[OF _ gts_sp])
  apply (rename_tac state)
  apply (case_tac state; clarsimp simp: assert_def)
   apply (wpsimp simp: set_simple_ko_def set_thread_state_def set_object_def
                a_type_def partial_inv_def wp: get_object_wp)
   apply (auto dest!: get_tcb_SomeD split: if_split_asm simp: pred_tcb_at_def obj_at_def runnable_eq)[1]
  apply (wpsimp simp: set_simple_ko_def set_thread_state_def set_object_def
       a_type_def partial_inv_def wp: get_object_wp)
  apply (auto dest!: get_tcb_SomeD split: if_split_asm simp: pred_tcb_at_def obj_at_def runnable_eq)[1]
  done

(* FIXME: move; this should be much higher up *)
lemma in_get_refs:
  "((p', r') \<in> get_refs r p) = (r' = r \<and> p = Some p')"
  by (auto simp: get_refs_def split: option.splits)

lemma runnable_not_queued:
  "\<lbrakk> st_tcb_at runnable t s; ko_at (Endpoint (RecvEP qs)) epptr s; t \<in> set qs;
     sym_refs (state_refs_of s) \<rbrakk>
  \<Longrightarrow> False"
  apply (frule st_tcb_at_state_refs_ofD)
  apply (frule (1) sym_refs_ko_atD)
  apply (clarsimp simp: obj_at_def)
  apply (drule (1) bspec)
  apply (clarsimp simp: state_refs_of_def in_get_refs)
  apply (auto simp: runnable_eq)
  done

lemma send_ipc_st_tcb_at_runnable:
  "\<lbrace>st_tcb_at runnable t and (\<lambda>s. sym_refs (state_refs_of s)) and K (thread \<noteq> t) \<rbrace>
   send_ipc block call badge can_grant can_donate thread epptr
   \<lbrace>\<lambda>rv. st_tcb_at runnable t\<rbrace>"
  unfolding send_ipc_def
  supply if_split[split del]
  apply (wpsimp wp: sts_st_tcb_at_other get_tcb_obj_ref_wp hoare_vcg_all_lift hoare_vcg_if_lift
                    reply_unlink_runnable get_simple_ko_wp | wp_once hoare_drop_imp)+
  apply (auto dest: runnable_not_queued)
  done

lemma receive_ipc_st_tcb_at_runnable:
  "\<lbrace>st_tcb_at runnable t and (\<lambda>s. sym_refs (state_refs_of s)) and K (thread \<noteq> t) \<rbrace>
   receive_ipc thread cap is_blocking reply_cap
   \<lbrace>\<lambda>rv. st_tcb_at runnable t\<rbrace>"
  unfolding receive_ipc_def
  apply (rule hoare_gen_asm)
  apply (wpc | wp sts_st_tcb_at_other get_simple_ko_wp get_tcb_obj_ref_wp hoare_vcg_all_lift
      | clarsimp simp: do_nbrecv_failed_transfer_def
      | wp_once hoare_drop_imp)+
(*
              apply (wp hoare_drop_imps)[1]
             apply clarsimp
             apply (wp hoare_drop_imps)[1]
            apply wpc
                   apply ((wp gts_wp gbn_wp  hoare_vcg_all_lift sts_st_tcb_at_other | wpc
                           | simp add: do_nbrecv_failed_transfer_def | wp_once hoare_drop_imps)+)[8]
           apply (wp gts_wp)
          apply (wp hoare_drop_imps hoare_vcg_all_lift)[1]
         apply ((wp sts_st_tcb_at_other get_simple_ko_wp gbn_wp get_simple_ko_wp | wpc)+)[8]
  apply clarsimp
  apply (rule conjI)
   apply clarsimp
   apply (rename_tac sendq)
   apply (frule list.collapse[symmetric])
   apply (drule st_tcb_at_state_refs_ofD)
   apply (frule (1) sym_refs_ko_atD)
   apply clarsimp
   apply (drule_tac x="hd sendq" in bspec, clarsimp)
   apply (case_tac ts; clarsimp simp: obj_at_def state_refs_of_def dest!: refs_in_tcb_bound_refs)
  apply clarsimp
  apply (rename_tac sendq)
  apply (frule list.collapse[symmetric])
  apply (drule st_tcb_at_state_refs_ofD)
  apply (frule (1) sym_refs_ko_atD)
  apply clarsimp
  apply (drule_tac x="hd sendq" in bspec, clarsimp)
  apply (case_tac ts; clarsimp simp: obj_at_def state_refs_of_def dest!: refs_in_tcb_bound_refs)
  done*) sorry

lemma send_fault_ipc_st_tcb_at_runnable:
  "\<lbrace>st_tcb_at runnable t and (\<lambda>s. sym_refs (state_refs_of s)) and tcb_at t' and K (t' \<noteq> t)\<rbrace>
   send_fault_ipc t' handler_cap fault can_donate \<lbrace>\<lambda>rv. st_tcb_at runnable t\<rbrace>"
  unfolding send_fault_ipc_def
  apply (rule hoare_pre, wp)
     apply wpc
                apply (wp send_ipc_st_tcb_at_runnable thread_set_no_change_tcb_state thread_set_refs_trivial
                          hoare_vcg_all_lift_R thread_get_wp
                        | clarsimp
                        | wp_once hoare_drop_imps)+
  done

lemma handle_fault_st_tcb_at_runnable:
  "\<lbrace>st_tcb_at runnable t and invs and K (t' \<noteq> t) \<rbrace>
    handle_fault t' x \<lbrace>\<lambda>rv. st_tcb_at runnable t\<rbrace>"
  apply (rule hoare_gen_asm)
  apply (simp add: handle_fault_def handle_no_fault_def)
  apply (wpsimp simp: unless_when wp: sts_st_tcb_at_other send_fault_ipc_st_tcb_at_runnable)
  apply (clarsimp dest!: get_tcb_SomeD simp: obj_at_def is_tcb)
  done

lemma handle_recv_st_tcb_at:
  "\<lbrace>invs and st_tcb_at runnable t and (\<lambda>s. cur_thread s \<noteq> t)\<rbrace> handle_recv True can_reply
  \<lbrace>\<lambda>rv s. st_tcb_at runnable t s\<rbrace>"
  apply (simp add: handle_recv_def Let_def ep_ntfn_cap_case_helper
             cong: if_cong split del: if_split)
  apply (rule hoare_pre) (*
   apply (wp handle_fault_st_tcb_at_runnable receive_ipc_st_tcb_at_runnable
             delete_caller_cap_sym_refs rai_pred_tcb_neq
             get_simple_ko_wp hoare_drop_imps hoare_vcg_all_lift_R)
    apply clarsimp
    apply wp+
  apply fastforce
  done *) sorry

end (* Lemmas related to preservation of runnability over handle_recv for woken threads *)

end

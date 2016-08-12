Require Import floyd.proofauto.
Import ListNotations.
Local Open Scope logic.
Require Import floyd.sublist.

Require Import sha.HMAC256_functional_prog.
Require Import sha.general_lemmas.
Require Import sha.spec_sha.

Require Import hmacdrbg.entropy.
Require Import hmacdrbg.entropy_lemmas.
Require Import hmacdrbg.DRBG_functions.
Require Import hmacdrbg.HMAC_DRBG_algorithms.
Require Import hmacdrbg.HMAC256_DRBG_functional_prog.
Require Import hmacdrbg.hmac_drbg.
Require Import hmacdrbg.HMAC_DRBG_pure_lemmas.
Require Import hmacdrbg.spec_hmac_drbg.
Require Import hmacdrbg.HMAC_DRBG_common_lemmas.
Require Import hmacdrbg.spec_hmac_drbg_pure_lemmas.

(*TEMPORARRY FIX TO DEAL WITH NAME SPACES*)
Axiom FINALNAME:_HMAC_Final = hmac._HMAC_Final. 
Axiom UPDATENAME:_HMAC_Update = hmac._HMAC_Update. 
Axiom INITNAME: _HMAC_Init = hmac._HMAC_Init. 
Axiom CTX_Struct: Tstruct hmac_drbg._hmac_ctx_st noattr = spec_hmac.t_struct_hmac_ctx_st.

(*
Inductive md_any (r: mdstate): mpred :=
  md_any_empty: md_empty r -> md_any r.
| md_any_rep: forall h r, md_relate h r -> md_any r
| md_any_full: forall k r, md_full k r -> md_any r.
*)

Lemma ReseedRes: forall X r v, @return_value_relate_result X r (Vint v) -> Int.eq v (Int.repr (-20864)) = false.
Proof. intros.
  unfold return_value_relate_result in H.
  destruct r. inv H; reflexivity.
  destruct e; inv H; try reflexivity.
  apply Int.eq_false. eapply ENT_GenErrAx. 
Qed.

Definition preseed_relate rc pr ri (r : hmac256drbgstate):mpred:=
    match r with
     (md_ctx', (V', (reseed_counter', (entropy_len', (prediction_resistance', reseed_interval'))))) =>
    md_empty md_ctx' &&
    !! (map Vint (map Int.repr initial_key) = V' /\
        Vint (Int.repr rc) = reseed_counter'(* /\
        Vint (Int.repr entropy_len) = entropy_len'*) /\
        Vint (Int.repr ri) = reseed_interval' /\
        Val.of_bool pr = prediction_resistance')
   end.

Axiom Entropy_add: forall n m s s1 s2 x1 x2, ENTROPY.get_bytes n s = ENTROPY.success x1 s1 ->
        ENTROPY.get_bytes m s1 = ENTROPY.success x2 s2 ->
        exists x, ENTROPY.get_bytes (n+m) s = ENTROPY.success x s2.

Axiom Entropy_addSuccess: forall n m s s1 x1, ENTROPY.get_bytes n s = ENTROPY.success x1 s1 ->
        ENTROPY.get_bytes (n+m) s = ENTROPY.get_bytes m s1.

Axiom Entropy_addError: forall n m s s1 e, ENTROPY.get_bytes n s = ENTROPY.error e s1 ->
        ENTROPY.get_bytes (n+m) s = ENTROPY.error e s1.

(*Entropy_add is derivable from Entropy_addStrong:*)
Goal forall n m s s1 s2 x1 x2, ENTROPY.get_bytes n s = ENTROPY.success x1 s1 ->
        ENTROPY.get_bytes m s1 = ENTROPY.success x2 s2 ->
        exists x, ENTROPY.get_bytes (n+m) s = ENTROPY.success x s2.
Proof. intros. rewrite (Entropy_addSuccess _ _ _ _ _ H), H0. eexists; trivial. Qed.

(*Parameter OptionalNonce: option (list Z).*)
Definition OptionalNonce: option (list Z) := None. (*The implementation takes nonce from entropy, using the el*3/2 calculation*)

Parameter max_personalization_string_length: Z. (*NIST SP 800-90A, page 38, Table2: 2^35 bits; 
         Our personalization nstring is a list of bytes, so have max length 2^32*)
Axiom max_personalization_string336: 336 <= max_personalization_string_length.

Parameter prediction_resistance_supported: bool.

(*NIST, Section 10.1: highest supported sec strength is given by the has function's
security strength for preimage resistance. For SHA256, this is 
(according to NIST SP 800-107, Table 1, page 11) 256 bits*)
Definition highest_supported_security_strength := 256. (*as in reseed; so in bits - but should it be in bytes?*)


(*Q: should we use the sec strength of HMAC, calculated according to Section 5.3.4 of 
NIST SP 800-107 instead?*)
Definition requested_instantiation_security_strength:= 32.  (*is this right?*)

Definition mbedtls_HMAC256_DRBG_init_function (entropy_stream: ENTROPY.stream) 
         entropy_len prediction_resistance (personalization_string: list Z): ENTROPY.result DRBG_state_handle :=
   let reseed_interval := 10000 
   in HMAC256_DRBG_instantiate_function entropy_len entropy_len OptionalNonce
            highest_supported_security_strength max_personalization_string_length
            prediction_resistance_supported entropy_stream
            requested_instantiation_security_strength prediction_resistance personalization_string.

Definition entlen:Z := 32.

Definition hmac_drbg_seed_spec :=
  DECLARE _mbedtls_hmac_drbg_seed
   WITH ctx: val, info:val, len: Z, data:val, Data: list Z,
        Ctx: hmac256drbgstate,
        (*CTX: hmac256drbgabs,*)
        kv: val, Info: md_info_state, s:ENTROPY.stream, rc:Z, pr:bool, ri:Z
    PRE [_ctx OF tptr (Tstruct _mbedtls_hmac_drbg_context noattr),
         _md_info OF tptr (Tstruct _mbedtls_md_info_t noattr),
         _custom OF tptr tuchar, _len OF tuint ] 
       PROP ( pr = prediction_resistance_supported (*For now*) /\
              (len = Zlength Data) /\ 
              0 <= len (*<= 336 Int.max_unsigned*) /\
              48 + len < Int.modulus /\
              0 < 48 + Zlength (contents_with_add data len Data) < Int.modulus /\ Forall isbyteZ Data)
       LOCAL (temp _ctx ctx; temp _md_info info; 
              temp _len (Vint (Int.repr len)); temp _custom data; gvar sha._K256 kv)
       SEP (
         data_at Tsh t_struct_hmac256drbg_context_st Ctx ctx;
         preseed_relate rc pr ri Ctx;
         (*hmac256drbg_relate CTX Ctx;*)
         data_at Tsh t_struct_mbedtls_md_info Info info;
         da_emp Tsh (tarray tuchar (Zlength Data)) (map Vint (map Int.repr Data)) data;
         K_vector kv; Stream s)
    POST [ tint ]
       EX ret_value:_,
       PROP ()
       LOCAL (temp ret_temp (Vint ret_value))
       SEP (data_at Tsh t_struct_mbedtls_md_info Info info;
            da_emp Tsh (tarray tuchar (Zlength Data)) (map Vint (map Int.repr Data)) data;
            K_vector kv;
            if Int.eq ret_value (Int.repr (-20864))
            then data_at Tsh t_struct_hmac256drbg_context_st Ctx ctx *
                  (*hmac256drbg_relate CTX Ctx *) preseed_relate rc pr ri Ctx * 
                  Stream s
            else md_empty (fst Ctx) * 
                 EX p:val, 
                 match (fst Ctx) with (M1, (M2, M3)) =>
                   if (zlt 256 (Zlength Data) || (zlt 384 (48 + Zlength Data)))%bool
                   then !!(ret_value = Int.repr (-5)) && 
                     (Stream s * 
                     ( let CtxFinal:= ((info, (M2, p)), (list_repeat 32 (Vint Int.one), (Vint (Int.repr rc), 
                                       (Vint (Int.repr 48), (Val.of_bool pr, Vint (Int.repr 10000)))))) in
                       let CTXFinal:= HMAC256DRBGabs initial_key (list_repeat 32 1) rc 48 pr 10000 in
                       data_at Tsh t_struct_hmac256drbg_context_st CtxFinal ctx *
                                     hmac256drbg_relate CTXFinal CtxFinal))

                   else (*let myABS := HMAC256DRBGabs VV (list_repeat 32 1) rc 48 pr 10000
                        in *) 
                        match mbedtls_HMAC256_DRBG_init_function s entlen pr (contents_with_add data (Zlength Data) Data)
                        with
                         | ENTROPY.error e ss => 
                            (!!(match e with
                               | ENTROPY.generic_error => Vint ret_value = Vint (Int.repr ENT_GenErr)
                               | ENTROPY.catastrophic_error => Vint ret_value = Vint (Int.repr (-9))
                              end) && (Stream ss * 
                                       let CtxFinal:= ((info, (M2, p)), (list_repeat 32 (Vint Int.one), (Vint (Int.repr rc), 
                                                (Vint (Int.repr 48), (Val.of_bool pr, Vint (Int.repr 10000)))))) in
                                       let CTXFinal:= HMAC256DRBGabs initial_key (list_repeat 32 1) rc 48 pr 10000 in
                                       data_at Tsh t_struct_hmac256drbg_context_st CtxFinal ctx *
                                       hmac256drbg_relate CTXFinal CtxFinal))
                        | ENTROPY.success handle ss => !!(ret_value = Int.zero) && 
                                    match handle with ((((newV, newK), newRC), newEL), newPR) =>
                                      let CtxFinal := ((info, (M2, p)), (map Vint (map Int.repr newV), (Vint (Int.repr newRC), (Vint (Int.repr 32), (Val.of_bool newPR, Vint (Int.repr 10000)))))) in
                                      let CTXFinal := HMAC256DRBGabs newK newV newRC 32 newPR 10000 in 
                                    data_at Tsh t_struct_hmac256drbg_context_st CtxFinal ctx *
                                    hmac256drbg_relate CTXFinal CtxFinal *
                                    Stream ss end 
                        end
                end).


(*let myABS := HMAC256DRBGabs VV (list_repeat 32 1) rc 48 pr 10000
                      in match mbedtls_HMAC256_DRBG_reseed_function s myABS
                                (contents_with_add data (Zlength Data) Data)
                         with
                         | ENTROPY.error e ss => 
                            (!!(match e with
                               | ENTROPY.generic_error => Vint ret_value = Vint (Int.repr ENT_GenErr)
                               | ENTROPY.catastrophic_error => Vint ret_value = Vint (Int.repr (-9))
                              end) && (Stream ss * 
                                       let CtxFinal:= ((info, (M2, p)), (list_repeat 32 (Vint Int.one), (Vint (Int.repr rc), 
                                                (Vint (Int.repr 48), (Val.of_bool pr, Vint (Int.repr 10000)))))) in
                                       let CTXFinal:= HMAC256DRBGabs VV (list_repeat 32 1) rc 48 pr 10000 in
                                       data_at Tsh t_struct_hmac256drbg_context_st CtxFinal ctx *
                                       hmac256drbg_relate CTXFinal CtxFinal))
                        | ENTROPY.success handle ss => !!(ret_value = Int.zero) && 
                                    match handle with ((((newV, newK), newRC), newEL), newPR) =>
                                      let CtxFinal := ((info, (M2, p)), (map Vint (map Int.repr newV), (Vint (Int.repr newRC), (Vint (Int.repr 32), (Val.of_bool newPR, Vint (Int.repr 10000)))))) in
                                      let CTXFinal := HMAC256DRBGabs newK newV newRC 32 newPR 10000 in 
                                    data_at Tsh t_struct_hmac256drbg_context_st CtxFinal ctx *
                                    hmac256drbg_relate CTXFinal CtxFinal *
                                    Stream ss end 
                        end
                end*)

Opaque mbedtls_HMAC256_DRBG_reseed_function.

Lemma FALSE: False. Admitted.

Lemma body_hmac_drbg_seed: semax_body HmacDrbgVarSpecs HmacDrbgFunSpecs 
      f_mbedtls_hmac_drbg_seed hmac_drbg_seed_spec. 
Proof. 
  start_function. 
  abbreviate_semax.
  destruct H as [PREQ [HDlen1 [HDlen2 [DHlen3 [DHlen4 HData]]]]]. 
  rewrite data_at_isptr with (p:=ctx). Intros.
  destruct ctx; try contradiction.
  unfold_data_at 1%nat.
  destruct Ctx as [MdCTX [V [RC [EL [PR RI]]]]]. simpl.
  destruct MdCTX as [M1 [M2 M3]].
  freeze [1;2;3;4;5] FIELDS.
  rewrite field_at_compatible'. Intros. rename H into FC_mdx.
  rewrite field_at_data_at. unfold field_address. simpl. rewrite if_true; trivial. rewrite int_add_repr_0_r. 
  freeze [0;2;3;4;5;6] FR0.
  Time forward_call ((M1,(M2,M3)), Vptr b i, Vint (Int.repr 1), info).
   (*8.5pl2: without FR0, this akes about 5mins but succeeds*)
  
  Intros v. rename H into Hv.
  forward.
  forward_if (
     PROP (v=0)
   LOCAL (temp _ret (Vint (Int.repr v)); temp 235%positive (Vint (Int.repr v));
   temp _ctx (Vptr b i); temp _md_info info; temp _len (Vint (Int.repr len));
   temp _custom data; gvar sha._K256 kv)
   SEP ( (EX p : val, !!field_compatible spec_hmac.t_struct_hmac_ctx_st [] p && memory_block Tsh (sizeof (Tstruct _hmac_ctx_st noattr)) p *
          data_at Tsh (Tstruct _mbedtls_md_context_t noattr) ((*M1*)info,(M2,p)) (Vptr b i));
         FRZL FR0)).
  { destruct Hv; try omega. rewrite if_false; trivial. clear H. subst v.
    forward. simpl. Exists (Int.repr (-20864)). 
    rewrite Int.eq_true. 
    entailer!. thaw FR0. cancel. 
    unfold_data_at 2%nat. thaw FIELDS. cancel.
    rewrite field_at_data_at. simpl.
    unfold field_address. rewrite if_true; simpl; trivial. rewrite int_add_repr_0_r; trivial. }
  { subst v. clear Hv. simpl. forward. entailer!. }
  Intros. subst v. clear Hv. Intros p. rename H into FC_P.

  (*Alloction / md_setup succeeded. Now get md_size*)
  drop_LOCAL 0%nat.
  drop_LOCAL 0%nat.
  forward_call tt.
 
  (*call mbedtls_md_hmac_starts( &ctx->md_ctx, ctx->V, md_size )*)
  thaw FR0. subst.
  (*rename H1 into ZL_VV. rename H2 into isbyteZ_VV.*)
  assert (ZL_VV: Zlength initial_key =32) by reflexivity.
  assert (isbyteZ_VV: Forall isbyteZ initial_key). 
  { unfold initial_key. simpl.
    repeat constructor; try split; try omega.
    (*even easier top prove once we use list_repeat in def of initial_key*) 
  }
  thaw FIELDS. 
  freeze [3;4;5;6] FIELDS1.
  rewrite field_at_compatible'. Intros. rename H into FC_V.
  rewrite field_at_data_at. unfold field_address. simpl. rewrite if_true; trivial.
  rewrite <- ZL_VV.
  freeze [0;4;5;6;8] FR2.
  replace_SEP 1 (UNDER_SPEC.EMPTY p).
  { entailer. apply protocol_spec_hmac.OPENSSL_HMAC_ABSTRACT_SPEC.mkEmpty. 
    clear - FC_P. unfold field_compatible in *.
    simpl in *. exfalso. apply FALSE. (*has contradiction in hypothesis - maybe malloc does not guarantee filed_compatible_at?? Or is it a compspecs issue*) }
  forward_call (Vptr b i, ((info,(M2,p)):mdstate), 32, initial_key, kv, b, Int.add i (Int.repr 12)).
(*  { rewrite ZL_VV, int_add_repr_0_r; simpl.
    apply prop_right; repeat split; trivial.
  }*)
  { simpl. cancel. }
  { split; trivial. red. simpl. rewrite int_max_signed_eq (*, ZL_VV*). 
    split. trivial. split. omega. rewrite two_power_pos_equiv.
    replace (2^64) with 18446744073709551616. omega. reflexivity.
  }
  Intros.
  
  (*call  memset( ctx->V, 0x01, md_size )*)
  freeze [0;1;3;4] FR3.
  forward_call (Tsh, Vptr b (Int.add i (Int.repr 12)), 32, Int.one).
(*  { rewrite ZL_VV; entailer!. 
  } *)
  { rewrite sepcon_comm. apply sepcon_derives. 
      eapply derives_trans. apply data_at_memory_block. 
        rewrite ZL_VV. simpl. cancel. cancel. }
  (*{ split. apply semax_call.writable_share_top.
    rewrite ZL_V0, client_lemmas.int_max_unsigned_eq. omega. }*)

  (*ctx->reseed_interval = MBEDTLS_HMAC_DRBG_RESEED_INTERVAL;*)
  rewrite ZL_VV. 
  thaw FR3. thaw FR2. unfold md_relate. simpl.
  thaw FIELDS1. forward.
  freeze [0;4;5;6;7] FIELDS2.
  freeze [0;1;2;3;4;5;6;7;8] ALLSEP.

(*  set (ent_len := new_ent_len (Zlength V0)) in *.*)

  forward_if 
  (PROP ( )
   LOCAL (temp _md_size (Vint (Int.repr 32)); temp _ctx (Vptr b i); temp _md_info info;
   temp _len (Vint (Int.repr (Zlength Data))); temp _custom data; gvar sha._K256 kv;
   temp 237%positive (Vint (Int.repr 32)))
   SEP (FRZL ALLSEP)).
  { forward. entailer. }
  { forward_if 
     (PROP ( )
      LOCAL (temp _md_size (Vint (Int.repr 32)); 
             temp _ctx (Vptr b i); temp _md_info info;
             temp _len (Vint (Int.repr (Zlength Data))); temp _custom data; gvar sha._K256 kv;
             temp 237%positive (Vint (Int.repr 32)))  
      SEP (FRZL ALLSEP)).
    { forward. forward. entailer. }
    { forward. forward. entailer. }
    { intros. (*FLOYD ERROR: entailer FAILS HERE*) 
      unfold overridePost.
      destruct (eq_dec ek EK_normal).
      { subst ek. (*entailer. STILL FAILS*) unfold POSTCONDITION, abbreviate.
        normalize. (*simpl. intros.*) apply andp_left2. normalize.
        old_go_lower.
        normalize. Time entailer. }
      { apply andp_left2. cancel. }
    }
  }
  forward. simpl. drop_LOCAL 7%nat. (*237%positive*) 

  (*NEXT INSTRUCTION:  ctx->entropy_len = entropy_len * 3 / 2*)
  thaw ALLSEP. thaw FIELDS2. forward.

  assert (FOURTYEIGHT: Int.unsigned (Int.mul (Int.repr 32) (Int.repr 3)) / 2 = 48).
  { rewrite mul_repr. simpl.
    rewrite Int.unsigned_repr. reflexivity. rewrite int_max_unsigned_eq; omega. }
  set (pr:= prediction_resistance_supported) in *.
  set (myABS := HMAC256DRBGabs initial_key (list_repeat 32 1) rc 48 pr  10000) in *. 
  assert (myST: exists ST:hmac256drbgstate, ST = 
    ((info, (M2, p)), (map Vint (list_repeat 32 Int.one), (Vint (Int.repr rc),
        (Vint (Int.repr 48), (Val.of_bool pr, Vint (Int.repr 10000))))))). eexists; reflexivity.
  destruct myST as [ST HST].

  freeze [0;1;2;3;4] FR_CTX.
  freeze [3;5;6;7] KVStreamInfoData.

  (*NEXT INSTRUCTION: mbedtls_hmac_drbg_reseed( ctx, custom, len ) *)
  freeze [1;2;3] INI. 
  specialize (Forall_list_repeat isbyteZ 32 1); intros IB1.
  replace_SEP 0 (
         data_at Tsh t_struct_hmac256drbg_context_st ST (Vptr b i) *
         hmac256drbg_relate myABS ST).
  { go_lower. thaw INI. clear KVStreamInfoData. thaw FR_CTX.
    unfold_data_at 3%nat.
    subst ST; simpl. cancel. normalize.
    apply andp_right. apply prop_right. repeat split; trivial. apply IB1. split; omega. 
    unfold md_full. simpl.
    rewrite field_at_data_at. simpl.
    unfold field_address. rewrite if_true; simpl; trivial. rewrite int_add_repr_0_r. cancel.
    rewrite field_at_data_at. simpl.
    unfold field_address. rewrite if_true; simpl; trivial. cancel. 
    apply protocol_spec_hmac.OPENSSL_HMAC_ABSTRACT_SPEC.REP_FULL.
  }

  clear INI.
  thaw KVStreamInfoData. freeze [6] OLD_MD. 
  forward_call (Data, data, Zlength Data, Vptr b i, ST, myABS, kv, Info, s).
  { unfold hmac256drbgstate_md_info_pointer.
    subst ST; simpl. cancel.
  }
  { subst myABS; simpl. rewrite <- initialize.max_unsigned_modulus in *.
    split. omega. (* rewrite int_max_unsigned_eq; omega.*)
    split. reflexivity.
    split. reflexivity.
    split. omega.
    split. (*change Int.modulus with 4294967296.*) omega.
    split. (* change Int.modulus with 4294967296.*)
       unfold contents_with_add. if_tac. omega. rewrite Zlength_nil; omega.
    split. apply IB1. split; omega.
    assumption.
  }

  Intros v. 
  assert (ZLc': Zlength (contents_with_add data (Zlength Data) Data) = 0 \/
                 Zlength (contents_with_add data (Zlength Data) Data) = Zlength Data).
         { unfold contents_with_add. if_tac. right; trivial. left; trivial. }
  forward. 
  forward_if (
   PROP ( v = nullval)
   LOCAL (temp _ret v; temp 240%positive v;
   temp _entropy_len (Vint (Int.repr 32));
   temp _md_size (Vint (Int.repr 32)); temp _ctx (Vptr b i);
   temp _md_info info;
   temp _len (Vint (Int.repr (Zlength Data)));
   temp _custom data; gvar sha._K256 kv)
   SEP (reseedPOST v Data data (Zlength Data) s
          myABS (Vptr b i) Info kv ST; FRZL OLD_MD)).
  { rename H into Hv. forward. simpl. Exists v.
    apply andp_right. apply prop_right; trivial. 
    apply andp_right. apply prop_right; split; trivial.
    unfold reseedPOST. 
    
    remember ((zlt 256 (Zlength Data) || zlt 384 (hmac256drbgabs_entropy_len myABS + Zlength Data)) %bool) as d.
    unfold myABS in Heqd; simpl in Heqd.
    destruct (zlt 256 (Zlength Data)); simpl in Heqd.
    + subst d. unfold hmac256drbgstate_md_info_pointer, hmac256drbg_relate; simpl. 
      simpl. subst myABS. normalize. simpl. cancel.
      Exists p. thaw OLD_MD. normalize. 
      apply andp_right. apply prop_right; repeat split; trivial. cancel.
    + destruct (zlt 384 (48 + Zlength Data)); simpl in Heqd; try omega. 
      subst d.
      unfold hmac256drbgstate_md_info_pointer, hmac256drbg_relate; simpl. normalize.
      rename H into RV.
      remember (mbedtls_HMAC256_DRBG_reseed_function s myABS
         (contents_with_add data (Zlength Data) Data)) as MRS.
      rewrite (ReseedRes _ _ _ RV). cancel.
      unfold return_value_relate_result in RV.
      assert (ZLc'256F: Zlength (contents_with_add data (Zlength Data) Data) >? 256 = false).
      { apply Zgt_is_gt_bool_f. destruct ZLc' as [ZLc' | ZLc']; rewrite ZLc'; trivial. omega. }
      unfold hmac256drbgabs_common_mpreds, hmac256drbgstate_md_info_pointer.
      destruct MRS.
      - exfalso. inv RV. simpl in Hv. discriminate.
      - simpl. normalize. Exists p. thaw OLD_MD. cancel.
        remember (mbedtls_HMAC256_DRBG_init_function s entlen pr (contents_with_add data (Zlength Data) Data)) as INIT.
        assert (ERR: INIT = ENTROPY.error ENTROPY.catastrophic_error s0 /\
                  e = ENTROPY.catastrophic_error).
        { unfold mbedtls_HMAC256_DRBG_init_function, HMAC256_DRBG_instantiate_function, DRBG_instantiate_function in HeqINIT; simpl in HeqINIT.
Transparent mbedtls_HMAC256_DRBG_reseed_function.
          unfold mbedtls_HMAC256_DRBG_reseed_function in HeqMRS. 
Opaque mbedtls_HMAC256_DRBG_reseed_function.
          subst myABS. simpl in HeqMRS. rewrite ZLc'256F in *. subst pr. rewrite andb_negb_r in *.
          assert (MaxString': Zlength (contents_with_add data (Zlength Data) Data) >?
                    max_personalization_string_length = false).
          { apply Zgt_is_gt_bool_f. specialize max_personalization_string336; intros.
            destruct ZLc' as [ZLc' | ZLc']; rewrite ZLc'; trivial; omega. }
          rewrite MaxString' in *.
          destruct prediction_resistance_supported; simpl in *.
          ++ unfold get_entropy in *. clear - g0 HeqMRS HeqINIT. unfold entlen in *. 
             remember (ENTROPY.get_bytes (Z.to_nat 48) s) as ENT. destruct ENT; try discriminate. 
             inv HeqMRS.
             remember (ENTROPY.get_bytes (Z.to_nat 32) s) as  ENT1; symmetry in HeqENT1.
             destruct ENT1; try discriminate. change (32 / 2) with 16 in *.
             remember (ENTROPY.get_bytes (Z.to_nat 16) s0) as  ENT2; symmetry in HeqENT2.
             destruct ENT2; try discriminate.
(*             destruct (Entropy_add _ _ _ _ _ _ _ HeqENT1 HeqENT2) as [x X].
             rewrite <-Z2Nat.inj_add in X; try omega. change (32+16) with 48 in *.
             rewrite X in HeqENT. discriminate.
             exists s2; split; trivial.
             exists s0; split; trivial.*)
             specialize (Entropy_addSuccess _ 16 _ _ _ HeqENT1); intros XX. simpl in *; rewrite XX in *; clear XX. rewrite HeqENT2 in HeqENT; discriminate.
             specialize (Entropy_addSuccess _ 16 _ _ _ HeqENT1); intros XX. simpl in *; rewrite XX in *; clear XX. rewrite HeqENT2 in HeqENT; inv HeqENT.
               split; trivial.
             specialize (Entropy_addError _ 16 _ _ _ HeqENT1); intros XX. simpl in *; rewrite XX in *; clear XX. inv HeqENT.
             split; trivial. 
          ++ unfold get_entropy in *. clear - g0 HeqMRS HeqINIT. unfold entlen in *. 
             remember (ENTROPY.get_bytes (Z.to_nat 48) s) as ENT. destruct ENT; try discriminate. 
             inv HeqMRS.
             remember (ENTROPY.get_bytes (Z.to_nat 32) s) as  ENT1; symmetry in HeqENT1.
             destruct ENT1; try discriminate. change (32 / 2) with 16 in *.
             remember (ENTROPY.get_bytes (Z.to_nat 16) s0) as  ENT2; symmetry in HeqENT2.
             destruct ENT2; try discriminate.
(*             destruct (Entropy_add _ _ _ _ _ _ _ HeqENT1 HeqENT2) as [x X].
             rewrite <-Z2Nat.inj_add in X; try omega. change (32+16) with 48 in *.
             rewrite X in HeqENT. discriminate.
             exists s2; split; trivial.
             exists s0; split; trivial.*)
             specialize (Entropy_addSuccess _ 16 _ _ _ HeqENT1); intros XX. simpl in *; rewrite XX in *; clear XX. rewrite HeqENT2 in HeqENT; discriminate.
             specialize (Entropy_addSuccess _ 16 _ _ _ HeqENT1); intros XX. simpl in *; rewrite XX in *; clear XX. rewrite HeqENT2 in HeqENT; inv HeqENT.
               split; trivial.
             specialize (Entropy_addError _ 16 _ _ _ HeqENT1); intros XX. simpl in *; rewrite XX in *; clear XX. inv HeqENT.
             split; trivial. 
             (*unfold get_entropy, entlen in *. clear - g0 HeqMRS HeqINIT. 
             remember (ENTROPY.get_bytes (Z.to_nat 48) s) as ENT. destruct ENT; try discriminate. 
             inv HeqMRS.
             remember (ENTROPY.get_bytes (Z.to_nat 32) s) as  ENT1; symmetry in HeqENT1.
             destruct ENT1; try discriminate. change (32 / 2) with 16 in *.
             remember (ENTROPY.get_bytes (Z.to_nat 16) s0) as  ENT2; symmetry in HeqENT2.
             destruct ENT2; try discriminate.
             destruct (Entropy_add _ _ _ _ _ _ _ HeqENT1 HeqENT2) as [x X].
             rewrite <-Z2Nat.inj_add in X; try omega. change (32+16) with 48 in *.
             rewrite X in HeqENT. discriminate.
             exists s2; split; trivial.
             exists s0; split; trivial.*)
          }
          (*destruct ERR as [ss [SS EE]];*) destruct ERR as [SS EE]. rewrite SS in *. clear SS. subst e.
          normalize.
          apply andp_right. apply prop_right; repeat split; trivial.
          cancel.
        (*}
        clear HeqINIT; subst INIT.
        unfold hmac256drbgabs_common_mpreds, hmac256drbgstate_md_info_pointer; simpl. normalize.
        Exists p. thaw OLD_MD. cancel. normalize. 
        apply andp_right. apply prop_right; repeat split; trivial.
        cancel.*)
  }
  { rename H into Hv. forward.
    go_lower. simpl in Hv. apply typed_false_of_bool in Hv. apply negb_false_iff in Hv.
    symmetry in Hv; apply binop_lemmas2.int_eq_true in Hv. subst v.
    entailer!.
  }
  Intros. subst v.
  unfold reseedPOST.
  remember ((zlt 256 (Zlength Data)
          || zlt 384 (hmac256drbgabs_entropy_len myABS + Zlength Data))%bool) as d.
  destruct d; Intros.
  remember (mbedtls_HMAC256_DRBG_reseed_function s myABS
         (contents_with_add data (Zlength Data) Data)) as MRS. 
  unfold return_value_relate_result in H.
  destruct MRS. Focus 2. exfalso. destruct e. inv H. 
                     destruct ENT_GenErrAx as [EL1 _]. rewrite <- H in EL1. elim EL1; trivial. 
  clear H. unfold hmac256drbgabs_reseed. rewrite <- HeqMRS. subst myABS; simpl.
  destruct d as [[[[newV newK] newRC] dd] newPR].
  unfold hmac256drbgabs_common_mpreds. simpl. subst ST. unfold hmac256drbgstate_md_info_pointer. simpl. Intros. 
  unfold_data_at 1%nat. freeze [0;1;2;4;5;6;7;8;9;10;11] XX.
  forward. forward.
  Exists Int.zero. simpl.
  apply andp_right. apply prop_right; trivial.
  apply andp_right. apply prop_right; split; trivial.
  symmetry in Heqd. apply orb_false_iff in Heqd. destruct Heqd as [Heqd1 Heqd2].
  destruct (zlt 256 (Zlength Data)); try discriminate. simpl in *. rewrite Heqd2.
  thaw XX. thaw OLD_MD. cancel.
  Exists p. normalize.
  assert (ZLc'256F: Zlength (contents_with_add data (Zlength Data) Data) >? 256 = false).
      { destruct ZLc' as [HH | HH]; rewrite HH. reflexivity.
        apply Zgt_is_gt_bool_f. omega. } 
  assert (MaxString': Zlength (contents_with_add data (Zlength Data) Data) >?
                    max_personalization_string_length = false).
          { apply Zgt_is_gt_bool_f. specialize max_personalization_string336; intros.
            destruct ZLc' as [ZLc' | ZLc']; rewrite ZLc'; trivial; omega. }
  remember (mbedtls_HMAC256_DRBG_init_function s entlen pr (contents_with_add data (Zlength Data) Data)) as INIT.
  assert (INIT = ENTROPY.success (newV, newK, newRC, entlen, newPR) s0).
  { unfold mbedtls_HMAC256_DRBG_init_function, HMAC256_DRBG_instantiate_function, DRBG_instantiate_function in HeqINIT; simpl in HeqINIT.
Transparent mbedtls_HMAC256_DRBG_reseed_function.
        unfold mbedtls_HMAC256_DRBG_reseed_function in HeqMRS. 
Opaque mbedtls_HMAC256_DRBG_reseed_function.
          rewrite MaxString' in *.
          destruct prediction_resistance_supported; simpl in *.
          ++ rewrite ZLc'256F in *. unfold get_entropy, entlen in *.
             remember (ENTROPY.get_bytes (Z.to_nat 48) s) as ENT.
             destruct ENT; inv HeqMRS.
             remember (ENTROPY.get_bytes (Z.to_nat 32) s) as ENT1. destruct ENT1.
             -- change (32/2) with 16. symmetry in HeqENT1.
                specialize (Entropy_addSuccess _ 16 _ _ _ HeqENT1); intros XX; simpl in *.
                rewrite XX in HeqENT; clear XX; inv HeqENT.
                unfold HMAC256_DRBG_instantiate_algorithm, HMAC_DRBG_instantiate_algorithm.
                symmetry in H5. rename l0 into l32. rename s0 into s32.
                rename l into l32_16. rename s1 into s32_16.
                remember (HMAC_DRBG_update HMAC256 (l32 ++ l32_16 ++ (contents_with_add data (Zlength Data) Data)) initial_key initial_value) as HMAC_B.
                remember (HMAC_DRBG_update HMAC256 (l32_16 ++ contents_with_add data (Zlength Data) Data) initial_key
                     [1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1;
                        1; 1; 1; 1; 1; 1]) as HMAC_A.
                destruct HMAC_A as [HMAC_AK HMAC_AV]. 
                destruct HMAC_B as [HMAC_BK HMAC_BV]. inv H4. 
                exfalso. apply FALSE. (*Discrepancy in arguments to HMAC_DRBG_update!*)
             -- symmetry in HeqENT1.
                specialize (Entropy_addError _ 16 _ _ _ HeqENT1); intros XX; simpl in *.
                rewrite XX in *; clear XX; discriminate.
          ++ rewrite ZLc'256F in *. unfold entlen, get_entropy in *.
             remember (ENTROPY.get_bytes (Z.to_nat 32) s) as ENT32; symmetry in HeqENT32.
             destruct ENT32.
             -- specialize (Entropy_addSuccess _ 16 _ _ _ HeqENT32); intros XX; simpl in *.
                rewrite XX in *.
                remember (ENTROPY.get_bytes 16 s1) as ENT32_16; symmetry in HeqENT32_16.
                destruct ENT32_16; try discriminate. inv HeqMRS.
                remember (HMAC_DRBG_update HMAC256 (l0 ++ contents_with_add data (Zlength Data) Data) initial_key
          [1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1; 1;
          1; 1; 1; 1]) as HMAC_A. 
                destruct HMAC_A as [HMAC_AK HMAC_AV]. inv H4. 
                unfold HMAC256_DRBG_instantiate_algorithm, HMAC_DRBG_instantiate_algorithm.
                rename l into l32. rename s1 into s32.
                rename l0 into l32_16. rename s2 into s32_16.
                remember (HMAC_DRBG_update HMAC256 (l32 ++ l32_16 ++ (contents_with_add data (Zlength Data) Data)) initial_key initial_value) as HMAC_B.
                destruct HMAC_B as [HMAC_BK HMAC_BV].
                exfalso. apply FALSE. (*same discrepancy in arguments to HMAC_DRBG_update!*)
             -- specialize (Entropy_addError _ 16 _ _ _ HeqENT32); intros XX; simpl in *.
                rewrite XX in *; discriminate.
  }
  rewrite H3 in *; clear H3. normalize.   
  apply andp_right. apply prop_right; repeat split; trivial. 
  unfold_data_at 1%nat. cancel.
Time Qed. (*75.219 secs (59.734u,0.s) (successful)*)

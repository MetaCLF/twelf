(* Splitting : Version 1.3 *)
(* Author: Carsten Schuermann *)

functor MTPSplitting (structure MTPGlobal : MTPGLOBAL
		      structure Global : GLOBAL
		      structure IntSyn : INTSYN
		      structure FunSyn : FUNSYN
			sharing FunSyn.IntSyn = IntSyn
		      structure StateSyn' : STATESYN
			sharing StateSyn'.FunSyn = FunSyn
		      structure MTPAbstract : MTPABSTRACT
			sharing MTPAbstract.IntSyn = IntSyn
		        sharing MTPAbstract.StateSyn = StateSyn'
		      structure MTPrint : MTPRINT
		        sharing MTPrint.StateSyn = StateSyn'
		      structure Whnf : WHNF
  		        sharing Whnf.IntSyn = IntSyn
		      structure TypeCheck : TYPECHECK
			sharing TypeCheck.IntSyn = IntSyn
		      structure Index : INDEX
		        sharing Index.IntSyn = IntSyn
		      structure Print : PRINT
		        sharing Print.IntSyn = IntSyn
		      structure Unify : UNIFY
		        sharing Unify.IntSyn = IntSyn) 
  : MTPSPLITTING =
struct
  structure StateSyn = StateSyn'

  exception Error of string

  (* Invariant: 
     Case analysis generates a list of successor states 
     (the cases) from a given state.

     'a flag marks cases where unification of the types
     succeeded as "Active", and cases where there were
     leftover constraints after unification as "Inactive".
     
     NB: cases where unification fails are not considered

     Consequence: Only those splitting operators can be
     applied which do not generate inactive cases (this
     can be checked for a given operator by applicable)
  *)
  datatype 'a flag = 
    Active of 'a | InActive

  type operator = (StateSyn.State * int) * 
		   StateSyn.State flag list

  local
    structure I = IntSyn
    structure F = FunSyn
    structure S = StateSyn


    (* createEVarSpineW (G, (V, s)) = ((V', s') , S')

       Invariant:
       If   G |- s : G1   and  G1 |- V = Pi {V1 .. Vn}. W : L
       and  G1, V1 .. Vn |- W atomic  
       then G |- s' : G2  and  G2 |- V' : L
       and  S = X1; ...; Xn; Nil
       and  G |- W [1.2...n. s o ^n] = V' [s']
       and  G |- S : V [s] >  V' [s']
    *)
    fun createEVarSpine (G, Vs) = createEVarSpineW (G, Whnf.whnf Vs)
    and createEVarSpineW (G, Vs as (I.Uni I.Type, s)) = (I.Nil, Vs) (* s = id *)
      | createEVarSpineW (G, Vs as (I.Root _, s)) = (I.Nil, Vs)   (* s = id *)
      | createEVarSpineW (G, (I.Pi ((D as I.Dec (_, V1), _), V2), s)) =  
	let 
	  val X = I.newEVar (G, I.EClo (V1, s))
	  val (S, Vs) = createEVarSpine (G, (V2, I.Dot (I.Exp (X), s)))
	in
	  (I.App (X, S), Vs)
	end

    (* createAtomConst (G, c) = (U', (V', s'))

       Invariant: 
       If   S |- c : Pi {V1 .. Vn}. V 
       then . |- U' = c @ (Xn; .. Xn; Nil)
       and  . |- U' : V' [s']
    *)
    fun createAtomConst (G, H) = 
      let
	val cid = (case H 
	             of (I.Const cid) => cid
		      | (I.Skonst cid) => cid)
	val V = I.constType cid
	val (S, Vs) = createEVarSpine (G, (V, I.id))
      in
	(I.Root (H, S), Vs)
      end

    (* createAtomBVar (G, k) = (U', (V', s'))

       Invariant: 
       If   G |- k : Pi {V1 .. Vn}. V 
       then . |- U' = k @ (Xn; .. Xn; Nil)
       and  . |- U' : V' [s']
    *)
    fun createAtomBVar (G, k) =
      let
	val I.Dec (_, V) = I.ctxDec (G, k)
	val (S, Vs) = createEVarSpine (G, (V, I.id))
      in
	(I.Root (I.BVar (k), S), Vs)
      end

    (* constCases (G, (V, s), I, abstract, ops) = ops'
     
       Invariant:
       If   G |- s : G'  G' |- V : type
       and  I a list of of constant declarations
       and  abstract an abstraction function
       and  ops a list of possible splitting operators
       then ops' is a list extending ops, containing all possible
	 operators from I
    *)
    fun constCases (G, Vs, nil, abstract, ops) = ops
      | constCases (G, Vs, I.Const c::Sgn, abstract, ops) = 
	let
	  val (U, Vs') = createAtomConst (G, I.Const c)
	in
	  constCases (G, Vs, Sgn, abstract,
		      Trail.trail (fn () => 
				   (if Unify.unifiable (G, Vs, Vs')
				      then Active (abstract U)
					   :: ops
				    else ops)
				   handle  MTPAbstract.Error _ => InActive :: ops))
	end

    (* paramCases (G, (V, s), k, abstract, ops) = ops'
     
       Invariant:
       If   G |- s : G'  G' |- V : type
       and  k a variable
       and  abstract an abstraction function
       and  ops a list of possible splitting operators
       then ops' is a list extending ops, containing all possible
	 operators introduced by parameters <= k in G
    *)
    fun paramCases (G, Vs, 0, abstract, ops) = ops
      | paramCases (G, Vs, k, abstract, ops) = 
	let 
	  val (U, Vs') = createAtomBVar (G, k)
	in
	  paramCases (G, Vs, k-1, abstract, 
		      Trail.trail (fn () =>
				   (if Unify.unifiable (G, Vs, Vs')
				      then Active (abstract U) :: ops
				    else ops)
				      handle  MTPAbstract.  Error _ => InActive  :: ops))
	end

    (* lowerSplitDest (G, (V, s'), abstract) = ops'
       
       Invariant: 
       If   G0, G |- s' : G1  G1 |- V: type
       and  G is the context of local parameters
       and  abstract abstraction function
       then ops' is a list of all operators unifying with V[s']
	    (it contains constant and parameter cases)
    *)
    fun lowerSplitDest (G, (V as I.Root (I.Const c, _), s'), abstract) =
          constCases (G, (V, s'), Index.lookup c, abstract, 
		      paramCases (G, (V, s'), I.ctxLength G, abstract, nil))
      | lowerSplitDest (G, (I.Pi ((D, P), V), s'), abstract) =
          let 
	    val D' = I.decSub (D, s')
	  in
	    lowerSplitDest (I.Decl (G, D'), (V, I.dot1 s'),
			    fn U => abstract (I.Lam (D', U)))
  	  end

    (* split (x:D, s, B, abstract) = ops'

       Invariant :
       If   |- G ctx
       and  |- B : G tags
       and  . |- s : G   and  G |- D : L
       and  abstract abstraction function
       then ops' = (op1, ... opn) are resulting operators from splitting D[s]
    *)
    fun split (D as I.Dec (_, V), s, B, abstract) = 
           lowerSplitDest (I.Null, (V, s), fn U' => abstract (I.Dot (I.Exp (U'), s), B))
      

    (* occursIn (k, U) = B, 

       Invariant:
       If    U in nf 
       then  B iff k occurs in U
    *)
    fun occursInExp (k, I.Uni _) = false
      | occursInExp (k, I.Pi (DP, V)) = occursInDecP (k, DP) orelse occursInExp (k+1, V)
      | occursInExp (k, I.Root (C, S)) = occursInCon (k, C) orelse occursInSpine (k, S)
      | occursInExp (k, I.Lam (D,V)) = occursInDec (k, D) orelse occursInExp (k+1, V)
      (* no case for Redex, EVar, EClo *)

    and occursInCon (k, I.BVar (k')) = (k = k')
      | occursInCon (k, I.Const _) = false
      | occursInCon (k, I.Def _) = false
      | occursInCon (k, I.Skonst _) = false
      (* no case for FVar *)

    and occursInSpine (_, I.Nil) = false
      | occursInSpine (k, I.App (U, S)) = occursInExp (k, U) orelse occursInSpine (k, S)
      (* no case for SClo *)

    and occursInDec (k, I.Dec (_, V)) = occursInExp (k, V)
    and occursInDecP (k, (D, _)) = occursInDec (k, D)

    fun isIndexInit k = false
    fun isIndexSucc (D, isIndex) k = occursInDec (k, D) orelse isIndex (k+1)  
    fun isIndexFail (D, isIndex) k = isIndex (k+1)


    fun abstractInit (S as S.State (n, (G, B), (IH, OH), d, O, H, F)) ((G', B'), s') = 
          (if !Global.doubleCheck then TypeCheck.typeCheckCtx G' else ();
	  S.State (n, (G', B'), (IH, OH), d, S.orderSub (O, s'), 
		   map (fn (i, F') => (i, F.forSub (F', s'))) H, F.forSub (F, s')))

    fun abstractFinal (abstract) (B, s) =
          abstract (MTPAbstract.abstractSub (B, s))

    fun abstractCont ((D, T), abstract) ((G, B), s) =  
          abstract ((I.Decl (G, Whnf.normalizeDec (D, s)),
		     I.Decl (B, T)), I.dot1 s)

    fun makeAddressInit S k = (S, k)
    fun makeAddressCont makeAddress k = makeAddress (k+1)

    (* expand' ((G, B), isIndex, abstract, makeAddress) = (s', ops')

       Invariant:
       If   |- G ctx
       and  |- B : G tags
       and  isIndex (k) = B function s.t. B holds iff k index
       and  abstract, dynamic abstraction function
       and  makeAddress, a function which calculates the index of the variable
	    to be split
       then . |- s' : G,  and s' = Xn ... X1 . ^0
       and  ops' is a list of splitting operators
 
       DOES NOT TREAT PARAMETERS YET!!!!!  -cs
    *)
    fun expand' ((I.Null, I.Null), isIndex, abstract, makeAddress) = 
          (I.id, nil)
      | expand' ((I.Decl (G, D), B' as I.Decl (B, T as (S.Assumption b))),
		 isIndex, abstract, makeAddress) = 
	  let 
	    val (s', ops) =
		expand' ((G, B), isIndexSucc (D, isIndex), 
			 abstractCont ((D, T), abstract),
			 makeAddressCont makeAddress)
	    val I.Dec (xOpt, V) = D
	    val X = I.newEVar (I.Null, I.EClo (V, s'))
	    val ops' = if not (isIndex 1) andalso b > 0
			   then 
			       (makeAddress 1, split (D, s', B', abstractFinal abstract))
			       :: ops
		       else ops
	  in
	    (I.Dot (I.Exp (X), s'), ops')
	  end
      | expand' ((I.Decl (G, D), B' as I.Decl (B, T as (S.Lemma (b, F.Ex _)))),
		 isIndex, abstract, makeAddress) = 
	  let 
	    val (s', ops) =
		expand' ((G, B), isIndexSucc (D, isIndex), 
			 abstractCont ((D, T), abstract),
			 makeAddressCont makeAddress)
	    val I.Dec (xOpt, V) = D
	    val X = I.newEVar (I.Null, I.EClo (V, s'))
	    val ops' = if not (isIndex 1) andalso b > 0
			   then 
			       (makeAddress 1, split (D, s', B', abstractFinal abstract))
			       :: ops
		       else ops
	  in
	    (I.Dot (I.Exp (X), s'), ops')
	  end
      | expand' ((I.Decl (G, D), I.Decl (B, T)), isIndex, abstract, makeAddress) = 
	  let 
	    val (s', ops) =
		expand' ((G, B), isIndexSucc (D, isIndex),
			 abstractCont ((D, T), abstract),
			 makeAddressCont makeAddress)
	    val I.Dec (xOpt, V) = D
	    val X = I.newEVar (I.Null, I.EClo (V, s'))
	  in
	    (I.Dot (I.Exp (X), s'), ops)
	  end



    (* expand (S) = ops'

       Invariant:
       If   |- S state
       then ops' is a list of all possiblie splitting operators
    *)
    fun expand (S as S.State (n, (G, B), (IH, OH), d, O, H, F)) =
      let 
	val (_, ops) =
	  expand' ((G, B), isIndexInit, abstractInit S, makeAddressInit S)
      in
	ops
      end

    (* index (Op) = k
       
       Invariant:
       If   Op = (_, Sl) 
       then k = |Sl| 
    *)
    fun index (_, Sl) = List.length Sl


    (* isInActive (F) = B
       
       Invariant:
       B holds iff F is inactive
    *)
    fun isInActive (Active _) = false
      | isInActive (InActive) = true


    (* applicable (Op) = B'

       Invariant: 
       If   Op = (_, Sl) 
       then B' holds iff Sl does not contain inactive states
    *)
    fun applicable (_, Sl) = not (List.exists isInActive Sl)


    (* apply (Op) = Sl'
       
       Invariant:
       If   Op = (_, Sl) 
       then Sl' = Sl
       
       Side effect: If Sl contains inactive states, an exception is raised
    *)
    fun apply (_, Sl) = 
      map (fn (Active S) => S
	    | InActive => raise Error "Not applicable: leftover constraints")
      Sl
      
		
    (* menu (Op) = s'
       
       Invariant:
       If   Op = ((S, i), Sl)  and  S is named
       then s' is a string describing the operation in plain text

       (menu should hence be only called on operators which have 
        been calculated from a named state)
    *)
    fun menu (Op as ((S.State (n, (G, B), (IH, OH), d, O, H, F), i), Sl)) = 
	let 
	  fun active (nil, n) = n
	    | active (InActive :: L, n) = active (L, n)
	    | active ((Active _) :: L, n) = active (L, n+1)

	  fun inactive (nil, n) = n
	    | inactive (InActive :: L, n) = inactive (L, n+1)
	    | inactive ((Active _) :: L, n) = inactive (L, n)

	  fun indexToString 0 = "zero cases"
	    | indexToString 1 = "1 case"
	    | indexToString n = (Int.toString n) ^ " cases"

	  fun flagToString (_, 0) = ""
	    | flagToString (n, m) = " [active: " ^(Int.toString n) ^ 
		" inactive: " ^ (Int.toString m) ^ "]"
	in
	  "Splitting : " ^ Print.decToString (G, I.ctxDec (G, i)) ^
	  " (" ^ (indexToString (index Op)) ^ 
	   (flagToString (active (Sl, 0), inactive (Sl, 0))) ^ ")"
	end

  in
    val expand = expand
    val menu = menu
    val applicable = applicable
    val apply = apply
    val index = index

  end (* local *)
end;  (* functor Splitting *)
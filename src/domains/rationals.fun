(* Rationals *)
(* Author: Roberto Virga *)

functor Rationals (Integer : INTEGER) : ORDERED_DOMAIN =
struct

  val name = "rational"

  exception Div = Div

  local
    structure I = Integer

    datatype number =                          (* Rational number:              *)
      Fract of Int.int * I.int * I.int         (* q := Fract (sign, num, denom) *)

    val zero = Fract (0,Integer.fromInt(0),Integer.fromInt(1))
    val one  = Fract (1,Integer.fromInt(1),Integer.fromInt(1))

    exception Div

    fun normalize (Fract (0, _, _)) = zero
      | normalize (Fract (s, n, d)) =
          let
            fun gcd (m, n) =
                  if (m = Integer.fromInt(0)) then n
                  else if (n = Integer.fromInt(0)) then m
                  else if I.>(m, n) then gcd (I.mod(m, n), n)
                  else gcd (m, I.mod(n, m))
            val g = gcd (n, d)
          in
            Fract (s, I.div(n, g), I.div(d, g))
          end

    fun op~ (Fract (s, n, d)) = (Fract (Int.~(s), n, d))

    fun op+ (Fract (s1, n1, d1), Fract (s2, n2, d2)) =
          let
            val n = I.+(I.*(I.*(I.fromInt(s1), n1), d2),
                        I.*(I.*(I.fromInt(s2), n2), d1))
          in
            normalize (Fract (I.sign(n), I.abs(n), I.*(d1, d2)))
          end

    fun op- (Fract (s1, n1, d1), Fract (s2, n2, d2)) =
          let
            val n = I.-(I.*(I.*(I.fromInt(s1), n1), d2),
                        I.*(I.*(I.fromInt(s2), n2), d1))
          in
            normalize (Fract (I.sign(n), I.abs(n), I.*(d1, d2)))
          end

    fun op* (Fract (s1, n1, d1), Fract (s2, n2, d2)) =
          normalize (Fract(Int.*(s1, s2), I.*(n1, n2), I.*(d1, d2)))

    fun inverse (Fract (0, _, _)) = raise Div
      | inverse (Fract (s, n, d)) = (Fract (s, d, n))

    fun sign (Fract (s, n, d)) = s

    fun abs (Fract (s, n, d)) = (Fract (Int.abs(s), n, d))

    fun compare (Fract (s1, n1, d1), Fract( s2, n2, d2)) =
          Integer.compare (I.*(I.*(I.fromInt(s1), n1), d2),
                           I.*(I.*(I.fromInt(s2), n2), d1))

    fun op> (q1, q2) = (compare (q1, q2) = GREATER)

    fun op< (q1, q2) = (compare (q1, q2) = LESS)

    fun op>= (q1, q2) = (q1 = q2) orelse (q1 > q2)

    fun op<= (q1, q2) = (q1 = q2) orelse (q1 < q2)

    fun fromInt (n) =
          (Fract (Int.sign (n),
                  Integer.fromInt (Int.abs (n)),
                  Integer.fromInt (1)))

    fun fromString (str) =
          let
            fun check_numerator (chars as (c :: chars')) =
                  if (c = #"~")
                  then (List.all Char.isDigit chars')
                  else (List.all Char.isDigit chars)
              | check_numerator nil =
                  false
            fun check_denominator (chars) =
                  (List.all Char.isDigit chars)
            val fields = (String.fields (fn c => (c = #"/")) str)
        in
          if (List.length fields = 1)
          then
            let
              val numerator = List.nth (fields, 0)
            in
              if (check_numerator (String.explode (numerator)))
              then
                case (Integer.fromString (numerator))
                  of SOME (n) => 
                       SOME (Fract(Integer.sign(n),
                                   Integer.abs(n),
                                   Integer.fromInt(1)))
                   | _ =>
                       NONE
              else
                NONE
            end
          else if (List.length fields = 2)
          then
            let
              val numerator = List.nth (fields, 0)
              val denominator = List.nth (fields, 1)
            in
              if (check_numerator (String.explode (numerator)))
                andalso (check_denominator (String.explode (denominator)))
              then
                case (Integer.fromString (numerator), Integer.fromString (denominator))
                  of (SOME (n), SOME (d)) =>
                       SOME (normalize (Fract (Integer.sign(n), Integer.abs(n), d)))
                   | _ =>
                       NONE
              else
                NONE
            end
          else
            NONE
        end

    fun toString (Fract(s, n, d)) =
          let
            val nStr = I.toString (I.* (I.fromInt(s), n))
            val dStr = Integer.toString d
          in
            if (d = I.fromInt(1)) then nStr else (nStr ^ "/" ^ dStr)
          end
  in
    type number = number

    val zero = zero
    val one = one

    val op~ = op~
    val op+ = op+
    val op- = op-
    val op* = op*
    val inverse = inverse

    val fromInt = fromInt
    val fromString = fromString
    val toString = toString

    val sign = sign
    val abs = abs

    val op> = op>
    val op< = op<
    val op>= = op>=
    val op<= = op<=
    val compare = compare
  end
end;  (* structure Rationals *)

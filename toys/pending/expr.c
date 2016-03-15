/* expr.c - evaluate expression
 *
 * Copyright 2013 Daniel Verkamp <daniel@drv.nu>
 *
 * http://pubs.opengroup.org/onlinepubs/9699919799/utilities/expr.html
 *
 * The web standard is incomplete (precedence grouping missing), see:
 * http://permalink.gmane.org/gmane.comp.standards.posix.austin.general/10141

USE_EXPR(NEWTOY(expr, NULL, TOYFLAG_USR|TOYFLAG_BIN))

config EXPR
  bool "expr"
  default n
  help
    usage: expr ARG1 OPERATOR ARG2...

    Evaluate expression and print result. For example, "expr 1 + 2".

    The supported operators are (grouped from highest to lowest priority):

      ( )    :    * / %    + -    != <= < >= > =    &    |

    Each constant and operator must be a separate command line argument.
    All operators are infix, meaning they expect a constant (or expression
    that resolves to a constant) on each side of the operator. Operators of
    the same priority (within each group above) are evaluated left to right.
    Parentheses may be used (as separate arguments) to elevate the priority
    of expressions.

    Calling expr from a command shell requires a lot of \( or '*' escaping
    to avoid interpreting shell control characters.

    The & and | operators are logical (not bitwise) and may operate on
    strings (a blank string is "false"). Comparison operators may also
    operate on strings (alphabetical sort).

    Constants may be strings or integers. Comparison, logical, and regex
    operators may operate on strings (a blank string is "false"), other
    operators require integers.
*/

// TODO: int overflow checking

#define FOR_expr
#include "toys.h"

GLOBALS(
  char* tok; // current token, not on the stack since recursive calls mutate it
)

// Values that expression operate over.
// s always points to an argv string, so we don't worry about memory
// allocation.
struct value {
  char *s;
  long long i;
  char valid_int;  // can we use the .i field?
};

/*
  // NOTE: because of the 'ret' overwriting, this is awkward.
  // I think we need to have the enum.  char tag == 0 for int and 1 for string.
  // and then every operator coerces?
  int get_int(v, &i)
  char[str]

  // re and cmp coerce_str
  // arithmetic does coerce int
  // this also makes memory management easier.  use stack buffers.
  // it might copy v->s into the buf.  That's fine.
  
  // is_false: check 'which' and do
  get_str(v, s);

  // note: he allows ot never free with xmalloc?  You can just xmalloc every
  // time?
  set_int(v, i);
  set_str(v, s);
*/

// check if v is the integer 0 or the empty string
static int is_zero(struct value *v)
{
  //return v->s ? !*v->s : !v->i;
  return v->valid_int ? v->i == 0 : !*v->s;
}

// Converts the value to a number and returns 1, or returns 0 if it can't be.
void maybe_fill_int(struct value *v) {
  //if (v->valid_int) return;
  char *endp;
  v->i = strtoll(v->s, &endp, 10);
  // If non-NULL, there are still characters left, and it's a string.
  v->valid_int = !*endp;
  //printf("%s is valid?  %d\n", v->s, v->valid_int);
}

// Converts a number back to a string, if it isn't already one.
void maybe_fill_string(struct value *v) {
  if (v->s) return;  // nothing to do
  static char num_buf[21];
  snprintf(num_buf, sizeof(num_buf), "%lld", v->i);
  v->s = num_buf;  // BUG!
}

/*
static char *num_to_str(long long num)
{
  static char num_buf[21];
  snprintf(num_buf, sizeof(num_buf), "%lld", num);
  return num_buf;
}
*/

static int cmp(struct value *lhs, struct value *rhs)
{
  if (lhs->valid_int && rhs->valid_int) {
    return lhs->i - rhs->i;
  } else {
    return strcmp(lhs->s, rhs->s);
  }
  /*
  if (lhs->s || rhs->s) {
    // at least one operand is a string
    char *ls = lhs->s ? lhs->s : num_to_str(lhs->i);
    char *rs = rhs->s ? rhs->s : num_to_str(rhs->i);
    // BUG: ls and rs are always the same static buffer!!!!
    return strcmp(ls, rs);
  } else return lhs->i - rhs->i;
  */
}

// Returns int position or string capture.
static void re(struct value *lhs, struct value *rhs)
{
  regex_t rp;
  regmatch_t rm[2];
  //printf("REGEX lhs %s  rhs %s\n", lhs->s, rhs->s);

  xregcomp(&rp, rhs->s, 0);
  // BUG: lhs->s is NULL when it looks like an integer, causing a segfault.
  if (!regexec(&rp, lhs->s, 2, rm, 0) && rm[0].rm_so == 0) { // matched
    //printf("matched\n");
    if (rp.re_nsub > 0 && rm[1].rm_so >= 0) {// has capture
      //printf("capture\n");
      lhs->s = xmprintf("%.*s", rm[1].rm_eo - rm[1].rm_so, lhs->s+rm[1].rm_so);
    } else {
      //printf("no capture\n");
      lhs->i = rm[0].rm_eo;
      lhs->valid_int = 1;
      lhs->s = 0;
    }
  } else { // no match
    //printf("no match\n");
    if (rp.re_nsub > 0) // has capture
      lhs->s = "";
    else {
      lhs->i = 0;
      lhs->valid_int = 1;
      lhs->s = 0;
    }
  }
}

static void mod(struct value *lhs, struct value *rhs)
{
  if (rhs->i == 0) error_exit("division by zero");
  lhs->i %= rhs->i;
}

static void divi(struct value *lhs, struct value *rhs)
{
  if (rhs->i == 0) error_exit("division by zero");
  lhs->i /= rhs->i;
}

static void mul(struct value *lhs, struct value *rhs)
{
  lhs->i *= rhs->i;
}

static void sub(struct value *lhs, struct value *rhs)
{
  lhs->i -= rhs->i;
}

static void add(struct value *lhs, struct value *rhs)
{
  lhs->i += rhs->i;
}

static void ne(struct value *lhs, struct value *rhs)
{
  lhs->i = cmp(lhs, rhs) != 0;
  lhs->s = NULL;
}

static void lte(struct value *lhs, struct value *rhs)
{
  lhs->i = cmp(lhs, rhs) <= 0;
  lhs->s = NULL;
}

static void lt(struct value *lhs, struct value *rhs)
{
  lhs->i = cmp(lhs, rhs) < 0;
  lhs->s = NULL;
}

static void gte(struct value *lhs, struct value *rhs)
{
  lhs->i = cmp(lhs, rhs) >= 0;
  lhs->s = NULL;
}

static void gt(struct value *lhs, struct value *rhs)
{
  lhs->i = cmp(lhs, rhs) > 0;
  lhs->s = NULL;
}

static void eq(struct value *lhs, struct value *rhs)
{
  lhs->i = !cmp(lhs, rhs);
  lhs->s = NULL;
}

static void and(struct value *lhs, struct value *rhs)
{
  if (is_zero(lhs) || is_zero(rhs)) {
    lhs->i = 0;
    lhs->s = NULL;
  }
}

static void or(struct value *lhs, struct value *rhs)
{
  if (is_zero(lhs)) *lhs = *rhs;
}

// Converts an arg string to a value struct.  Assumes arg != NULL.
static void parse_value(char* arg, struct value *v)
{
  char *endp;
  v->i = strtoll(arg, &endp, 10);
  // if non-NULL, there's still stuff left, and it's a string.  Otherwise no
  // string.
  v->s = *endp ? arg : NULL;
}

void syntax_error(char *msg, ...) {
  if (1) { // detailed message for debugging.  TODO: add CFG_ var to enable
    va_list va;
    va_start(va, msg);
    verror_msg(msg, 0, va);
    va_end(va);
    xexit();
  } else
    error_exit("syntax error");
}

// 4 different signatures of operators.  S = string, I = int, SI = string or
// int.
enum { XX, SI_TO_SI, SI_TO_I, I_TO_I, S_TO_SI };

enum { XXX, OR, AND, EQ, NE, GT, GTE, LT, LTE, ADD, SUB, MUL, DIVI, MOD, RE };

// operators grouped by precedence
static struct op_def {
  char *tok;
  char prec;
  // calculate "lhs op rhs" (e.g. lhs + rhs) and store result in lhs
  void (*calc)(struct value *lhs, struct value *rhs);
} OPS[] = {
  // uses is_zero
  {"|", 1, or  },
  {"&", 2, and },

  // all of these call cmp, so they use .i or .s in lhs.i, give 0 or 1 in lhs.i
  // they might coerce an int to string.
  {"=", 3, eq  }, {"==", 3, eq  }, {">",  3, gt  }, {">=", 3, gte },
  {"<", 3, lt  }, {"<=", 3, lte }, {"!=", 3, ne  },

  // requires ints in lhs.i and rhs.i, use lhs.i.
  {"+", 4, add }, {"-",  4, sub },
  {"*", 5, mul }, {"/",  5, divi }, {"%", 5, mod },

  // requires strings
  {":", 6, re  },

  {"",  0, NULL}, // sentinel
};

// Point TT.tok at the next token.  It's NULL when there are no more tokens.
void advance() {
  TT.tok = *toys.optargs++;
}

void eval_op(struct op_def *o, struct value *ret, struct value *rhs) {
  // Operators in a precedence class also have the same type coercion rules.
  int sig = 0;  // o->sig
  int op = 0;   // o->op

  // x = a OP b, and tri is for cmp()
  long long a, b, x, tri;

  // should arithmetic expressions always set the string part too?
  switch (sig) {

  case SI_TO_SI:
    switch (op) {
    case OR:  or (ret, &rhs); break;
    case AND: and(ret, &rhs); break;
    }
    break;  

  case SI_TO_I:
    // comparisons try ints first, then strings.
    // If they're not both ints, then make sure they are both strings.  A
    // bare int can be the result of arithmetic.
    /*
    if (!check_int(ret) || !check_int(&rhs)) {
      to_string(ret);
      to_string(&rhs);
    }
    */
    // cmp
    switch (op) {
    case EQ:  x = tri == 0; break;
    case NE:  x = tri != 0; break;
    case GT:  x = tri >  0; break;
    case GTE: x = tri >= 0; break;
    case LT:  x = tri <  0; break;
    case LTE: x = tri <= 0; break;
    }
    // now set
    break;

  case I_TO_I:
    /*
    if (!check_int(ret) || !check_int(&rhs)) {
      error_exit("non-integer argument");
    }
    */
    switch (op) {
    case ADD:  x = a + b; break;
    case SUB:  x = a - b; break;
    case MUL:  x = a * b; break;
    case DIVI: x = a / b; break;
    case MOD:  x = a % b; break;
    }

    break;

  case S_TO_SI:
    // coerce both args to strings
    // call re(s1, s2, ret) function, getting value
    /*
    to_string(ret);
    to_string(&rhs);
    */
    break;
  }
}

// Evalute a compound expression, setting 'ret'.
//
// This function uses the recursive "Precedence Climbing" algorithm:
//
// Clarke, Keith. "The top-down parsing of expressions." University of London.
// Queen Mary College. Department of Computer Science and Statistics, 1986.
//
// http://www.antlr.org/papers/Clarke-expr-parsing-1986.pdf
//
// Nice explanation and Python implementation:
// http://eli.thegreenplace.net/2012/08/02/parsing-expressions-by-precedence-climbing
static void eval_expr(struct value *ret, int min_prec)
{
  if (!TT.tok) syntax_error("Unexpected end of input");

  // Evaluate LHS atom, setting 'ret'.
  if (!strcmp(TT.tok, "(")) { // parenthesized expression
    advance(); // consume (
    eval_expr(ret, 1); // We're inside ( ), so start with min_prec = 1
    if (!TT.tok)             syntax_error("Expected )");
    if (strcmp(TT.tok, ")")) syntax_error("Expected ) but got %s", TT.tok);
    advance(); // consume )
  } else { // simple literal
    ret->s = TT.tok;  // everything is a valid string
    maybe_fill_int(ret);
    advance();
  }

  // Evaluate RHS and apply operator until precedence is too low.
  struct value rhs;
  while (TT.tok) {
    struct op_def *o = OPS;
    while (o->calc) {  // Look up the precedence of operator TT.tok
      if (!strcmp(TT.tok, o->tok)) break;
      o++;
    }
    if (!o->calc) break; // Not an operator (extra input will fail later)
    char prec = o->prec;
    if (prec < min_prec) break; // Precedence too low, pop a stack frame
    advance();

    eval_expr(&rhs, prec + 1); // Evaluate RHS, with higher min precedence

    maybe_fill_int(ret);
    maybe_fill_int(&rhs);
    if (prec == 4 || prec == 5) { // arithmetic error checking
      if (!ret->valid_int || !rhs.valid_int) error_exit("non-integer argument");
    }
    o->calc(ret, &rhs); // Apply operator, setting 'ret'.
    if (prec == 4 || prec == 5) {
      ret->s = NULL;  // not strings
    }
    maybe_fill_string(ret); // integer results might be used as strings

    eval_op(o, ret, &rhs);
  }
}

void expr_main(void)
{
  struct value ret = {0};
  toys.exitval = 2; // if exiting early, indicate invalid expression

  advance(); // initialize global token
  eval_expr(&ret, 1);

  if (TT.tok) syntax_error("Unexpected extra input '%s'\n", TT.tok);

  if (ret.valid_int) printf("%lld\n", ret.i);
  else printf("%s\n", ret.s);

  exit(is_zero(&ret));
}

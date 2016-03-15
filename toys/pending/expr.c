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
};

#define INT_BUF_SIZE 21

// Get the value as an string.
void get_str(struct value *v, char* ret)
{
  if (v->s)
    snprintf(ret, INT_BUF_SIZE, "%s", v->s);  // TODO: use strncpy
  else
    snprintf(ret, INT_BUF_SIZE, "%lld", v->i);
}

// Get the value as an integer and return 1, or return 0 on error.
int get_int(struct value *v, long long *ret)
{
  if (v->s) {
    char *endp;
    *ret = strtoll(v->s, &endp, 10);
    return *endp ? 0 : 1; // If endp points to NUL, all chars were converted
  } else {
    *ret = v->i;
    return 1;
  }
}

// Preserve the invariant that v.s is NULL when the value is an integer.
void assign_int(struct value *v, long long i)
{
  v->i = i;
  v->s = NULL;
}

// check if v is the integer 0 or the empty string
static int is_false(struct value *v)
{
  //return v->s ? !*v->s : !v->i;
  if (v->s)
    return !*v->s || !strcmp(v->s, "0");  // 0 is false
  else
    return !v->i;
}

// Converts the value to a number and returns 1, or returns 0 if it can't be.
void maybe_fill_int(struct value *v) {
  //if (v->valid_int) return;
  char *endp;
  v->i = strtoll(v->s, &endp, 10);
  // If non-NULL, there are still characters left, and it's a string.
  //v->valid_int = !*endp;
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

  /*
static int cmp(struct value *lhs, struct value *rhs)
{
  if (lhs->valid_int && rhs->valid_int) {
    return lhs->i - rhs->i;
  } else {
    return strcmp(lhs->s, rhs->s);
  }
  if (lhs->s || rhs->s) {
    // at least one operand is a string
    char *ls = lhs->s ? lhs->s : num_to_str(lhs->i);
    char *rs = rhs->s ? rhs->s : num_to_str(rhs->i);
    // BUG: ls and rs are always the same static buffer!!!!
    return strcmp(ls, rs);
  } else return lhs->i - rhs->i;
}
  */

// Returns int position or string capture.
static void re(char *target, char *pat, struct value *ret)
{
  regex_t rp;
  regmatch_t rm[2];
  //printf("REGEX lhs %s  rhs %s\n", lhs->s, rhs->s);

  xregcomp(&rp, pat, 0);
  // BUG: lhs->s is NULL when it looks like an integer, causing a segfault.
  if (!regexec(&rp, target, 2, rm, 0) && rm[0].rm_so == 0) { // matched
    //printf("matched\n");
    if (rp.re_nsub > 0 && rm[1].rm_so >= 0) {// has capture
      //printf("capture\n");
      ret->s = xmprintf("%.*s", rm[1].rm_eo - rm[1].rm_so, target+rm[1].rm_so);
    } else {
      //printf("no capture\n");
      assign_int(ret, rm[0].rm_eo);
    }
  } else { // no match
    //printf("no match\n");
    if (rp.re_nsub > 0) // has capture
      ret->s = "";
    else {
      assign_int(ret, 0);
    }
  }
}

/*
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
*/

static void and(struct value *lhs, struct value *rhs)
{
  if (is_false(lhs) || is_false(rhs)) {
    lhs->i = 0;
    lhs->s = NULL;
  }
}

static void or(struct value *lhs, struct value *rhs)
{
  if (is_false(lhs)) *lhs = *rhs;
}

/*
// Converts an arg string to a value struct.  Assumes arg != NULL.
static void parse_value(char* arg, struct value *v)
{
  char *endp;
  v->i = strtoll(arg, &endp, 10);
  // if non-NULL, there's still stuff left, and it's a string.  Otherwise no
  // string.
  v->s = *endp ? arg : NULL;
}
*/

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

/*
// operators grouped by precedence
static struct op_def {
  char *tok;
  char prec;
  // calculate "lhs op rhs" (e.g. lhs + rhs) and store result in lhs
  void (*calc)(struct value *lhs, struct value *rhs);
} OPS[] = {
  // uses is_false
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
*/

// operators grouped by precedence
static struct op_def {
  char *tok;
  char prec, sig, op; // precedence, signature for type coercion, operator ID
} OPS[] = {
  // logical ops, prec 1 and 2, sig SI_TO_SI
  {"|", 1, SI_TO_SI, OR  },
  {"&", 2, SI_TO_SI, AND },
  // comparison ops, prec 3, sig SI_TO_I
  {"=", 3, SI_TO_I, EQ }, {"==", 3, SI_TO_I, EQ  }, {"!=", 3, SI_TO_I, NE },
  {">", 3, SI_TO_I, GT }, {">=", 3, SI_TO_I, GTE },
  {"<", 3, SI_TO_I, LT }, {"<=", 3, SI_TO_I, LTE }, 
  // arithmetic ops, prec 4 and 5, sig I_TO_I
  {"+", 4, I_TO_I, ADD }, {"-",  4, I_TO_I, SUB },
  {"*", 5, I_TO_I, MUL }, {"/",  5, I_TO_I, DIVI }, {"%", 5, I_TO_I, MOD },
  // regex match
  {":", 6, S_TO_SI, RE },
  {NULL, 0, 0, 0}, // sentinel
};

// Point TT.tok at the next token.  It's NULL when there are no more tokens.
void advance() {
  TT.tok = *toys.optargs++;
}

void eval_op(struct op_def *o, struct value *ret, struct value *rhs) {
  long long a, b, x; // x = a OP b for ints.
  // OOPS.  These have to be longer than 21!
  char s[INT_BUF_SIZE], t[INT_BUF_SIZE]; // string operands
  int cmp;
  char op = o->op;

  switch (o->sig) {

  case SI_TO_SI:
    switch (op) {
    case OR:  or (ret, rhs); break;
    case AND: and(ret, rhs); break;
    }
    break;  

  case SI_TO_I:
    if (get_int(ret, &a) && get_int(rhs, &b)) {
      cmp = a - b;
    } else {  // if both aren't ints, compare both as strings
      get_str(ret, s);
      get_str(rhs, t);
      cmp = strcmp(s, t);
    }
    switch (op) {
    case EQ:  x = cmp == 0; break;
    case NE:  x = cmp != 0; break;
    case GT:  x = cmp >  0; break;
    case GTE: x = cmp >= 0; break;
    case LT:  x = cmp <  0; break;
    case LTE: x = cmp <= 0; break;
    }
    assign_int(ret, x);
    break;

  case I_TO_I:
    if (!get_int(ret, &a) || !get_int(rhs, &b))
      error_exit("non-integer argument");
    switch (op) {
    case ADD:  x = a + b; break;
    case SUB:  x = a - b; break;
    case MUL:  x = a * b; break;
    case DIVI: 
      if (b == 0) error_exit("division by zero");
      x = a / b;
      break;
    case MOD:
      if (b == 0) error_exit("division by zero");
      x = a % b;
      break;
    }
    assign_int(ret, x);
    break;

  case S_TO_SI: // op == RE
    get_str(ret, s);
    get_str(rhs, t);
    re(s, t, ret);
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
    ret->s = TT.tok; // everything starts off as a string
    //maybe_fill_int(ret);
    advance();
  }

  // Evaluate RHS and apply operator until precedence is too low.
  struct value rhs;
  while (TT.tok) {
    struct op_def *o = OPS;
    while (o->tok) {  // Look up the precedence of operator TT.tok
      if (!strcmp(TT.tok, o->tok)) break;
      o++;
    }
    if (!o->tok) break; // Not an operator (extra input will fail later)
    if (o->prec < min_prec) break; // Precedence too low, pop a stack frame
    advance();

    eval_expr(&rhs, o->prec + 1); // Evaluate RHS, with higher min precedence
    eval_op(o, ret, &rhs);

    /*
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
    */
  }
}

void expr_main(void)
{
  struct value ret = {0};
  toys.exitval = 2; // if exiting early, indicate invalid expression

  advance(); // initialize global token
  eval_expr(&ret, 1);

  if (TT.tok) syntax_error("Unexpected extra input '%s'\n", TT.tok);

  if (ret.s) printf("%s\n", ret.s);
  else printf("%lld\n", ret.i);

  exit(is_false(&ret));
}

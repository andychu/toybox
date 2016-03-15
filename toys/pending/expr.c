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
  int argidx;
  char* tok; // current token, not on the stack since recursive calls mutate it
)

// Scalar value.
// If s is NULL, the value is an integer (i).
// If s is not NULL, the value is a string (s).
struct value {
  char *s;
  long long i;
};

// check if v is the integer 0 or the empty string
static int is_zero(struct value *v)
{
  return v->s ? !*v->s : !v->i;
}

static char *num_to_str(long long num)
{
  static char num_buf[21];
  snprintf(num_buf, sizeof(num_buf), "%lld", num);
  return num_buf;
}

static int cmp(struct value *lhs, struct value *rhs)
{
  if (lhs->s || rhs->s) {
    // at least one operand is a string
    char *ls = lhs->s ? lhs->s : num_to_str(lhs->i);
    char *rs = rhs->s ? rhs->s : num_to_str(rhs->i);
    return strcmp(ls, rs);
  } else return lhs->i - rhs->i;
}

static void re(struct value *lhs, struct value *rhs)
{
  regex_t rp;
  regmatch_t rm[2];

  xregcomp(&rp, rhs->s, 0);
  // SEGFAULT: lhs->s is NULL.  parse_op keeps passing it
  if (!regexec(&rp, lhs->s, 2, rm, 0) && rm[0].rm_so == 0) {
    if (rp.re_nsub > 0 && rm[1].rm_so >= 0) 
      lhs->s = xmprintf("%.*s", rm[1].rm_eo - rm[1].rm_so, lhs->s+rm[1].rm_so);
    else {
      lhs->i = rm[0].rm_eo;
      lhs->s = 0;
    }
  } else {
    if (!rp.re_nsub) {
      lhs->i = 0;
      lhs->s = 0;
    } else lhs->s = "";
  }
}

static void mod(struct value *lhs, struct value *rhs)
{
  if (lhs->s || rhs->s) error_exit("non-integer argument");
  if (is_zero(rhs)) error_exit("division by zero");
  lhs->i %= rhs->i;
}

static void divi(struct value *lhs, struct value *rhs)
{
  if (lhs->s || rhs->s) error_exit("non-integer argument");
  if (is_zero(rhs)) error_exit("division by zero");
  lhs->i /= rhs->i;
}

static void mul(struct value *lhs, struct value *rhs)
{
  if (lhs->s || rhs->s) error_exit("non-integer argument");
  lhs->i *= rhs->i;
}

static void sub(struct value *lhs, struct value *rhs)
{
  if (lhs->s || rhs->s) error_exit("non-integer argument");
  lhs->i -= rhs->i;
}

static void add(struct value *lhs, struct value *rhs)
{
  if (lhs->s || rhs->s) error_exit("non-integer argument");
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

static void get_value(struct value *v)
{
  char *endp, *arg;

  if (TT.argidx == toys.optc) {
    v->i = 0;
    v->s = ""; // signal end of expression
    return;
  }

//  can't happen, the increment is after the == test
//  if (TT.argidx >= toys.optc) error_exit("syntax error");

  arg = toys.optargs[TT.argidx++];

  v->i = strtoll(arg, &endp, 10);
  // if non-NULL, there's still stuff left, and it's a string.  Otherwise no
  // string.
  v->s = *endp ? arg : NULL;
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

// check if v matches a token, and consume it if so
static int match(struct value *v, char *tok)
{
  if (v->s && !strcmp(v->s, tok)) {
    get_value(v);
    return 1;
  }

  return 0;
}

// operators in order of increasing precedence
static struct op {
  char *tok;

  // calculate "lhs op rhs" (e.g. lhs + rhs) and store result in lhs
  void (*calc)(struct value *lhs, struct value *rhs);
} ops[] = {
  {"|",   or  }, {"&",   and }, {"=",   eq  }, {"==",  eq  }, {">",   gt  },
  {">=",  gte }, {"<",   lt  }, {"<=",  lte }, {"!=",  ne  }, {"+",   add },
  {"-",   sub }, {"*",   mul }, {"/",   divi}, {"%",   mod }, {":",   re  },
  {"(",   NULL}, // special case - must be last
};

// operators grouped by precedence
static struct op2 {
  char *tok;
  char prec;

  // calculate "lhs op rhs" (e.g. lhs + rhs) and store result in lhs
  void (*calc)(struct value *lhs, struct value *rhs);
} OPS[] = {
  {"|", 1, or  },
  {"&", 2, and },
  {"=", 3, eq  }, {"==", 3, eq  }, {">",  3, gt  }, {">=", 3, gte },
  {"<", 3, lt  }, {"<=", 3, lte }, {"!=", 3, ne  },
  {"+", 4, add }, {"-",  4, sub },
  {"*", 5, mul }, {"/",  5, divi }, {"%", 5, mod },
  {":", 6, re  },
  {"",  0, NULL}, // sentinel
};

// "|,&,= ==> >=< <= !=,+-,*/%,:"

static void parse_op(struct value *lhs, struct value *tok, struct op *op)
{
  //printf("parse_op: lhs->s = %s\n", lhs->s);
  //printf("parse_op op = %p\n", op);
  // oh this is weird as hell, it just cycles around and around.
  //
  // and then if it doesn't match, it doesn't do anything.  geez.
  if (!op) op = ops;

  // special case parsing for parentheses
  if (*op->tok == '(') {
    if (match(tok, "(")) {
      parse_op(lhs, tok, 0);
      if (!match(tok, ")")) error_exit("syntax error"); // missing closing paren
    } else {
      // tok is a string or integer - return it and get the next token
      *lhs = *tok;
      get_value(tok);
    }

    return;
  }

  // doesn't this waste stack space?
  parse_op(lhs, tok, op + 1);
  while (match(tok, op->tok)) {
    // PROBLEM: prematurely converted to integer in : case
    // all the other operators which take strings as LHS also take integers
    //printf("tok->s: %s, op->tok: %s\n", tok->s, op->tok);
    struct value rhs;
    parse_op(&rhs, tok, op + 1);
    if (rhs.s && !*rhs.s) error_exit("syntax error"); // premature end of expression
    //printf("lhs->s = %s\n", lhs->s);
    op->calc(lhs, &rhs);
  }
}

void syntax_error(char *msg) {
  fprintf(stderr, "%s\n", msg);
  exit(2);
}

// point TT.tok at the next token.  It is NULL to indicate the end.
void advance() {
  TT.tok = *toys.optargs;
  toys.optargs++;
}

// 'lhs' is mutated.
static void eval_expr(struct value *lhs, int min_prec)
{
  if (!TT.tok) syntax_error("Unexpected end of expression");

  // parse LHS atom
  if (!strcmp(TT.tok, "(")) {  // parenthesized expression
    advance(); // consume (
    eval_expr(lhs, 1);  // inside ( ) means we start with min_prec = 1
    if (!TT.tok)             syntax_error("Expected )");
    if (strcmp(TT.tok, ")")) syntax_error("Expected ) but got");
    advance(); // consume )
  } else { // simple literal
    parse_value(TT.tok, lhs);
    advance();
  }

  // evaluate operators until precedence is too low.
  struct value rhs;
  while (TT.tok) {
    //printf("token: %s\n", TT.tok);
    struct op2 *o = OPS;
    while (o->calc) {  // TT.tok is an operator token, look it up
      if (!strcmp(TT.tok, o->tok)) {
        //printf("OP %s, PREC %d\n", o->tok, o->prec);
        break;
      }
      o++;
    }
    if (!o->calc) break; // not an operator (extra input will fail later)
    if (o->prec < min_prec) break; // precedence too low for this frame
    advance();

    eval_expr(&rhs, o->prec + 1); // get RHS value
    o->calc(lhs, &rhs); // apply operator
  }
}

void expr_main(void)
{
  struct value tok, ret = {0};

  toys.exitval = 2; // if exiting early, indicate invalid expression

  TT.argidx = 0;

  get_value(&tok); // warm up the parser with the initial value

  advance();
  eval_expr(&ret, 1);

  if (TT.tok) syntax_error("Got extra input: %s\n");//, TT.tok);

  //parse_op(&ret, &tok, 0);

  // final token should be end of expression
  //if (!tok.s || *tok.s) error_exit("syntax error");

  if (ret.s) printf("%s\n", ret.s);
  else printf("%lld\n", ret.i);

  exit(is_zero(&ret));
}

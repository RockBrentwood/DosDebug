// This program reads in the various data files, performs some checks, and spits out the tables needed for assembly and disassembly.
// The input files are:
//	Op.set	the instruction set,
//	Op.key	the translation from one- or two-character keys to operand list types,
//	Op.ord	the ordering relations to enforce on the operands.
// The output tables are written to DebugTab.inc, which is included into Debug.asm.

#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <stdbool.h>
#include <ctype.h>
#include <errno.h>

const int ShiftM = 12; // The number of bits below the CPU type.
const bool SortOps = false; // Sort the operator mnemonics.

#define Members(X) (sizeof (X)/sizeof *(X))

int KeyN = 0;
typedef struct KeyT *KeyT;
struct KeyT { short Key, Value, Width; };

#define TypeMax 82
int Keys = 0;
struct KeyT KeyDict[TypeMax];
char *NameTab[TypeMax]; // Contains the lines of Op.key.
int OffsetTab[TypeMax];
bool IsSmall[TypeMax];

#define OrdMax 30
int Ords = 0; KeyT Ord0[OrdMax], Ord1[OrdMax];

// Equates for the assembler table.
// These should be the same as in Debug.asm.
typedef enum {
   Mach0A = 0xed, Mach6A = 0xf3, LockableA = 0xf4, LockRepA = 0xf5, SegA = 0xf6, AaxA = 0xf7,
   D16A = 0xf8, D32A = 0xf9, WaitA = 0xfa, OrgA = 0xfb, DdA = 0xfc, DwA = 0xfd, DbA = 0xfe, EndA = 0xff
} AsmOp;
#define AsmMax 0x800
int Asms = 0; AsmOp AsmTab[AsmMax];

typedef struct OpT *OpT;
struct OpT {
   OpT Next;
   char *Id;
   short Len;
   short Offset; // ???
   short AsmOffset; // Offset in AsmTab.
};
#define OpMax 400
int Ops; struct OpT OpList[OpMax]; OpT OpBase;
#define SavedMax 10
int Saveds = 0; int SavedTab[SavedMax];
#define SlashMax 20
int Slashes; int SlashSeq[SlashMax], SlashOp[SlashMax];
#define HashMax 15
int Hashes; int HashSeq[HashMax], HashOp[HashMax];
#define StarMax 15
int Stars; int StarSeq[StarMax], StarOp[StarMax];
#define LockMax 50
int Locks; int LockTab[LockMax];
#define AGroupMax 14
int AGroups; int AGroupI[AGroupMax], AGroupInf[AGroupMax];

volatile void Fatal(const char *Format, ...) {
   va_list AP; va_start(AP, Format), vfprintf(stderr, Format, AP), va_end(AP);
   putc('\n', stderr);
   exit(EXIT_FAILURE);
}

const char *File; int Line;

FILE *OpenRead(const char *Path) {
   FILE *InF = fopen(Path, "r"); if (InF == NULL) perror(Path), exit(EXIT_FAILURE);
   File = Path, Line = 0;
   return InF;
}

volatile void Error(const char *Format, ...) {
   fprintf(stderr, "Line %d of `%s': ", Line, File);
   va_list AP; va_start(AP, Format), vfprintf(stderr, Format, AP), va_end(AP);
   putc('\n', stderr);
   exit(EXIT_FAILURE);
}

void *Allocate(unsigned N, const char *Why) {
   void *X = malloc(N); if (X == NULL) Fatal("Cannot allocate %u bytes for %s", N, Why);
   return X;
}

char LineBuf[132];
const size_t LineMax = Members(LineBuf);

bool GetLine(FILE *InF) {
   while (fgets(LineBuf, LineMax, InF) != NULL) {
      Line++;
      if (LineBuf[0] == '#') continue;
      int N = strlen(LineBuf) - 1;
      if (N > 0 && LineBuf[N] == '\r') LineBuf[N--] = '\0';
      if (N < 0 || LineBuf[N] != '\n') Error("too long.");
      if (N > 0) { LineBuf[N] = '\0'; return true; }
   }
   return false;
}

short GetKey(char **SP) {
   char *S = *SP;
   if (*S == ' ' || *S == '\t' || *S == ';' || *S == '\0') Error("key expected");
   short Key = *S++;
   if (*S != ' ' && *S != '\t' && *S != ';' && *S != '\0') {
      Key = (Key << 8) | *S++;
      if (*S != ' ' && *S != '\t' && *S != ';' && *S != '\0') Error("key too long");
   }
   *SP = S;
   return Key;
}

// Mark the given key pointer as small, as well as anything that, according to Op.ord, is smaller than it.
void MarkSmall(KeyT K) {
   IsSmall[K - KeyDict] = true;
   for (int o = 0; o < Ords; o++) if (Ord1[o] == K) MarkSmall(Ord0[o]);
}

// Add the bytecode Op to the assembler table (AsmTab).
// The format of this table is described in a long comment in Debug.asm, somewhere within the mini-assembler.
void AddAsm(AsmOp Op) {
   if (Asms >= AsmMax) Error("Assembler table overflow.");
   AsmTab[Asms++] = Op;
}

unsigned char GetCPU(char **SP) {
   char *S = *SP;
   if (*S != ';') return '\0';
   S++;
   if (*S < '0' || *S > '6') Error("bad machine type");
   unsigned char CPU = *S++ - '0';
   AddAsm((AsmOp)(Mach0A + CPU));
   *SP = S;
   return CPU;
}

KeyT LookUpKey(short Key) {
   for (KeyT K = KeyDict; K < KeyDict + Members(KeyDict); K++) if (Key == K->Key) return K;
   Error("can't find key %x", Key);
   return NULL;
}

static inline KeyT FindKey(char **SP) { return LookUpKey(GetKey(SP)); }

char *SpaceOver(char *S) {
   for (; *S == ' ' || *S == '\t'; S++);
   return S;
}

// Data and setup stuff for the disassembler processing.
// Data on coprocessor groups.
unsigned FpGroupTab[] = { 0xd9e8, 0xd9f0, 0xd9f8 };

#define NGROUPS     9
#define GROUP(G)    (0x100 + 010*((G) - 1))
#define COPR(O)     (0x100 + 010*NGROUPS + 0x10*(O))
#define FPGROUP(G)  (0x100 + 010*(NGROUPS + 0x10 + (G)))
#define SPARSE_BASE (0x100 + 010*(NGROUPS + 0x10 + Members(FpGroupTab)))

#if 0
#   define OPILLEGAL 0
#endif
#define OPTWOBYTE   2
#define OPGROUP     4
#define OPCOPR      6
#define OPFPGROUP   8
#define OPPREFIX    10
#define OPSIMPLE    12
#define OPTYPES     12 // Op types start here (includes simple ops).
#define PRESEG      1 // These should be the same as in Debug.asm.
#define PREREP      2
#define PREREPZ     4
#define PRELOCK     8
#define PRE32D      0x10
#define PRE32A      0x20

// For sparsely filled parts of the opcode map, we have counterparts to the above, which are compressed in a simple way.
// Sparse coprocessor groups.
unsigned SpFpGroupTab[] = { 0xd9d0, 0xd9e0, 0xdae8, 0xdbe0, 0xded8, 0xdfe0 };

#define NSGROUPS 5
#define SGROUP(G)	(SPARSE_BASE + 0x100 + 010*((G) - 1))
#define SFPGROUP(G)	(SPARSE_BASE + 0x100 + 010*(NSGROUPS + (G)))
#define NOPS		(SPARSE_BASE + 0x100 + 010*(NSGROUPS + Members(SpFpGroupTab)))

int OpType[NOPS], OpInfo[NOPS];
unsigned char OpCPU[NOPS];

// (Sequence, Group) number pair.
typedef struct GroupT { int Seq, Info; } *GroupT;

// Here are the tables for the main processor groups.
struct GroupT GroupTab[] = {
// Intel group 1.
   { 0x80, GROUP(1) }, { 0x81, GROUP(1) }, { 0x83, GROUP(2) },
// Intel group 2.
   { 0xd0, GROUP(3) }, { 0xd1, GROUP(3) }, { 0xd2, GROUP(4) }, { 0xd3, GROUP(4) },
// Intel group 2a.
   { 0xc0, GROUP(5) }, { 0xc1, GROUP(5) },
// Intel group 3.
   { 0xf6, GROUP(6) }, { 0xf7, GROUP(6) },
// Intel group 5.
   { 0xff, GROUP(7) },
// Intel group 6.
   { SPARSE_BASE + 0x00, GROUP(8) },
// Intel group 7.
   { SPARSE_BASE + 0x01, GROUP(9) }
};

// Sparse groups.
struct GroupT SpGroupTab[] = {
// Intel group 4.
   { 0xfe, SGROUP(1) },
// Intel group 8.
   { SPARSE_BASE + 0xba, SGROUP(2) },
// Intel group 9.
   { SPARSE_BASE + 0xc7, SGROUP(3) },
// Not an Intel group.
   { 0x8f, SGROUP(4) },
// Not an Intel group.
   { 0xc6, SGROUP(5) }, { 0xc7, SGROUP(5) }
};

// Add an entry to the disassembler lookup table.
void AddDas(int Op, int Type, int Info) {
   if (OpType[Op] != 0) Error("Duplicate information for index %d", Op);
   OpType[Op] = Type, OpInfo[Op] = Info;
}

// Get a hex nybble from the input line or fail.
int GetHex(char Ch) {
   if (!isxdigit(Ch)) { Error("Hex digit expected instead of `%c'", Ch); return -1; }
   else if (isdigit(Ch)) return Ch - '0';
   else if (islower(Ch)) return Ch - 'a' + 10;
   else return Ch - 'A' + 10;
}

// Get a hex byte from the input line and update the pointer accordingly.
int GetByte(char **SP) {
   char *S = *SP;
   int H0 = GetHex(*S++), H1 = GetHex(*S++);
   *SP = S;
   return H0 << 4 | H1;
}

// Get a `/r' descriptor from the input line and update the pointer accordingly.
int GetR(char **SP) {
   char *S = *SP;
   if (*S != '/') Error("`/' expected");
   S++;
   if (*S < '0' || *S > '7') Error("Octal digit expected");
   int R = *S++ - '0';
   *SP = S;
   return R;
}

// Add an item to OpList[].
int GetOp(char *S, char *EndS) {
   if (Ops >= OpMax) Error("Too many mnemonics");
   if (*S == '+') {
      if (Saveds >= SavedMax) Error("Too many mnemonics to save");
      SavedTab[Saveds++] = Ops, S++;
   }
   size_t Len = EndS - S;
   char *Id = Allocate(Len + 1, "mnemonic name");
   OpList[Ops].Id = Id, OpList[Ops].Len = Len;
#if 1
   for (; S < EndS; S++) *Id++ = toupper(*S);
   *Id = '\0';
#else
   memcpy(Id, S, Len), Id[Len] = '\0', _strupr(Id);
#endif
   OpList[Ops].AsmOffset = Asms;
   return Ops++;
}

// Merge-sort the indicated range of mnemonic records.
OpT SortOp(OpT Tab, int N) {
   if (!SortOps) return Tab;
   int n = N/2; if (n == 0) return Tab;
   OpT P0 = SortOp(Tab, n), P1 = SortOp(Tab + n, N - n);
   OpT Op, *OpP = &Op;
   while (true)
      if (strcmp(P0->Id, P1->Id) < 0) {
         *OpP = P0, OpP = &P0->Next, P0 = *OpP;
         if (P0 == NULL) { *OpP = P1; break; }
      } else {
         *OpP = P1, OpP = &P1->Next, P1 = *OpP;
         if (P1 == NULL) { *OpP = P0; break; }
      }
   return Op;
}

// Read the main file, "Op.set".
void GetOps(FILE *InF) {
   AddDas(0017, OPTWOBYTE, SPARSE_BASE);
   AddDas(0046, OPPREFIX, PRESEG | (0 << 8)); // ES:
   AddDas(0056, OPPREFIX, PRESEG | (1 << 8)); // CS:
   AddDas(0066, OPPREFIX, PRESEG | (2 << 8)); // SS:
   AddDas(0076, OPPREFIX, PRESEG | (3 << 8)); // DS:
   AddDas(0144, OPPREFIX, PRESEG | (4 << 8)); // FS:
   AddDas(0145, OPPREFIX, PRESEG | (5 << 8)); // GS:
   AddDas(0362, OPPREFIX, PREREP); // repne/repnz
   AddDas(0363, OPPREFIX, PREREP | PREREPZ); // repe/repz/rep
   AddDas(0360, OPPREFIX, PRELOCK); // lock:
   AddDas(0146, OPPREFIX, PRE32D); // D32:
   AddDas(0147, OPPREFIX, PRE32A); // A32:
   OpCPU[0144] = OpCPU[0145] = OpCPU[0146] = OpCPU[0147] = 3;
   for (int G = 0; G < Members(GroupTab); G++) AddDas(GroupTab[G].Seq, OPGROUP, GroupTab[G].Info);
   for (int S = 0; S < Members(SpGroupTab); S++) AddDas(SpGroupTab[S].Seq, OPGROUP, SpGroupTab[S].Info);
   for (int I = 0; I < 8; I++) AddDas(0xd8 + I, OPCOPR, COPR(I));
   for (int F = 0; F < Members(FpGroupTab); F++) {
      unsigned J = FpGroupTab[F], K = (J >> 8) - 0xd8;
      if (K > 010 || (J&0xff) < 0xc0) Fatal("Bad value for FpGroupTab[%d]", F);
      AddDas(COPR(K) + 010 + (((J&0xff) - 0xc0) >> 3), OPFPGROUP, FPGROUP(F));
   }
   for (int S = 0; S < Members(SpFpGroupTab); S++) {
      unsigned J = SpFpGroupTab[S], K = (J >> 8) - 0xd8;
      if (K > 010 || (J&0xff) < 0xc0) Fatal("Bad value for SpFpGroupTab[%d]", S);
      AddDas(COPR(K) + 010 + (((J&0xff) - 0xc0) >> 3), OPFPGROUP, SFPGROUP(S));
   }
   while (GetLine(InF)) { // Loop through the lines in the file.
      char *S = LineBuf;
      bool AsmOnlyLine = false; if (*S == '_') AsmOnlyLine = true, S++;
      unsigned char OpSuffix = '\0';
      if (*S == '^') {
         static const unsigned char UpTab[] = { AaxA, DbA, DwA, DdA, OrgA, D32A };
         S++, OpSuffix = UpTab[*S++ - '0'];
      }
      char *S1 = strchr(S, ' '); if (S1 == NULL) S1 = S + strlen(S);
   // Check for '/', '#' and '*' separators.
      char *SlashP = memchr(S, '/', S1 - S), *HashP = memchr(S, '#', S1 - S), *StarP = memchr(S, '*', S1 - S);
      int Op0, Op1;
      if (SlashP != NULL) {
         Op0 = GetOp(S, SlashP), AddAsm(D16A);
#if 0
         OpList[Op0].AsmOffset++; // This one isn't 32-bit.
#endif
         SlashP++, Op1 = GetOp(SlashP, S1), AddAsm(D32A);
      } else if (HashP != NULL) {
         Op0 = GetOp(S, HashP), AddAsm(D16A);
#if 0
         OpList[Op0].AsmOffset++; // This one isn't 32-bit.
#endif
         HashP++, Op1 = GetOp(HashP, S1), AddAsm(D32A);
      } else if (StarP != NULL)
      // Note the reversal.
         Op1 = GetOp(S, StarP), AddAsm(WaitA), StarP++, Op0 = GetOp(StarP, S1);
      else
         Op0 = GetOp(S, S1);
      if (OpSuffix != '\0') AddAsm((AsmOp)OpSuffix);
      OpSuffix = EndA;
      memset(IsSmall, 0, KeyN*sizeof *IsSmall);
      while (*S1 == ' ') { // Loop through the instruction variants.
         for (; *S1 == ' '; S1++);
         bool AsmOnly = AsmOnlyLine || *S1 == '_', DisOnly = *S1 == 'D';
         if (*S1 == '_' || *S1 == 'D') S1++;
         bool Lockable = *S1 == 'L';
         if (Lockable) {
            S1++;
            if (!DisOnly) AddAsm(LockableA);
         }
         unsigned long OpInf = GetByte(&S1);
         int OpX = OpInf;
         if (OpX == 0x0f) OpX = GetByte(&S1), OpInf = 0x100 + OpX, OpX += SPARSE_BASE;
         if (OpType[OpX] == OPGROUP) {
            int R = GetR(&S1), G = 0;
            for (; ; G++) {
               if (G >= AGroups) {
                  if (++AGroups > AGroupMax) Error("Too many agroup entries");
                  AGroupI[G] = OpX, AGroupInf[G] = OpInf;
                  break;
               }
               if (AGroupI[G] == OpX) break;
            }
            OpInf = 0x240 + 010*G + R, OpX = OpInfo[OpX] + R;
         }
         unsigned char OpExtra = 0;
         if (OpType[OpX] == OPCOPR) {
            if (*S1 == '/') {
               int R = GetR(&S1);
               OpInf = 0x200 + 010*R + (OpX - 0xd8), OpX = OpInfo[OpX] + R;
            } else {
               OpExtra = GetByte(&S1); if (OpExtra < 0xc0) Error("Bad second escape byte");
               OpX = OpInfo[OpX] + 010 + ((OpExtra - 0xc0) >> 3);
               if (OpType[OpX] == OPFPGROUP) OpX = OpInfo[OpX] + (OpExtra&7);
            }
         }
         unsigned short OpKey;
         switch (*S1++) {
         // None of these are lockable.
            case '.': {
               unsigned char CPU = GetCPU(&S1);
               if (!AsmOnly) AddDas(OpX, OPSIMPLE, Op0), OpCPU[OpX] = CPU;
               OpKey = 0;
            }
            break;
         // Lock or rep... prefix, including OpInf as a special case.
            case '*': AddAsm(LockRepA), AddAsm((AsmOp)(OpInf&0xff)), OpSuffix = '\0'; break;
         // Segment prefix, including OpInf as a special case.
            case '&': AddAsm(SegA), AddAsm((AsmOp)(OpInf&0xff)), OpSuffix = '\0'; break;
            case ':': {
               KeyT K = FindKey(&S1);
               int Width = K->Width;
               unsigned char CPU = GetCPU(&S1);
               if (DisOnly)/* OpSuffix = '\0'*/;
               else {
                  if (IsSmall[K - KeyDict]) Error("Variants out of order.");
                  MarkSmall(K);
               }
               OpKey = K->Value + 1;
               if (OpX >= 0x100 && OpX < SPARSE_BASE || OpX >= SPARSE_BASE + 0x100) {
                  if (Width > 2) Error("width failure");
                  Width = 1;
               }
               if (OpX&(Width - 1)) Error("width alignment failure");
               if (!AsmOnly) for (int J = (OpX == 0x90)/* A kludge for the NOP instruction. */; J < Width; J++) {
                  AddDas(OpX | J, OffsetTab[K->Value], Op0), OpCPU[OpX | J] = CPU;
                  if (Lockable) {
                     if (Locks >= LockMax) Error("Too many lockable instructions");
                     LockTab[Locks++] = OpX | J;
                  }
               }
            }
            break;
            default: Error("Syntax error.");
         }
         if (OpSuffix != '\0' && !DisOnly) {
            OpInf = OpInf*(unsigned short)(Keys + 1) + OpKey;
            AddAsm((AsmOp)(OpInf >> 8));
            if ((OpInf >> 8) >= Mach0A) Fatal("Assembler table is too busy");
            AddAsm((AsmOp)(OpInf&0xff));
            if (OpExtra != 0) AddAsm((AsmOp)OpExtra);
         }
         if (SlashP != NULL) {
            if (Slashes >= SlashMax) Error("Too many slash entries");
            SlashSeq[Slashes] = OpX, SlashOp[Slashes] = Op1, Slashes++;
         } else if (HashP != NULL) {
            if (Hashes >= HashMax) Error("Too many hash entries");
            HashSeq[Hashes] = OpX, HashOp[Hashes] = Op1, Hashes++;
         } else if (StarP != NULL) {
            if (Stars >= StarMax) Error("Too many star entries");
            StarSeq[Stars] = OpX, StarOp[Stars] = Op1, Stars++;
         }
      }
      if (*S1 != '\0') Error("Syntax error.");
      if (OpSuffix != '\0') AddAsm((AsmOp)OpSuffix); // EndA, if applicable.
   }
}

// Strings to put into the comment fields.
struct InfoRec {
   int Seq; char *Id;
} CommentTab[] = {
   { 0, "main opcode part" },
   { GROUP(1), "Intel group 1" },
   { GROUP(3), "Intel group 2" },
   { GROUP(5), "Intel group 2a" },
   { GROUP(6), "Intel group 3" },
   { GROUP(7), "Intel group 5" },
   { GROUP(8), "Intel group 6" },
   { GROUP(9), "Intel group 7" },
   { COPR(0), "Coprocessor d8" },
   { COPR(1), "Coprocessor d9" },
   { COPR(2), "Coprocessor da" },
   { COPR(3), "Coprocessor db" },
   { COPR(4), "Coprocessor dc" },
   { COPR(5), "Coprocessor dd" },
   { COPR(6), "Coprocessor de" },
   { COPR(7), "Coprocessor df" },
   { FPGROUP(0), "Coprocessor groups" },
   { -1, NULL }
};

// Print a "dw" list; add a newline every 8 items.
void _PutDw(FILE *ExF, int *Tab, int N) {
   for (; N > 0; N -= 8) {
      const char *InitS = "\tdw ";
      for (int n = (N <= 8? N: 8); n > 0; n--) fprintf(ExF, "%s%04xh", InitS, *Tab++), InitS = ",";
      putc('\n', ExF);
   }
}

// Print a labeled "dw" list; add a newline every 8 items.
static inline void PutDw(FILE *ExF, const char *Label, int *Tab, int N) { fputs(Label, ExF), _PutDw(ExF, Tab, N); }

void PutPairs(FILE *ExF, const char *Label, int Seq[], int Op[], size_t N) {
   fprintf(ExF, "%s1", Label), _PutDw(ExF, Seq, N);
#if 0
   for (int n = 0; n < N; n++) Op[n] = OpList[Op[n]].Offset;
   fprintf(ExF, "%s2", Label), _PutDw(ExF, Seq, N);
#else
   fprintf(ExF, "%s2 label word\n", Label);
   for (int n = 0; n < N; n++) fprintf(ExF, "\tdw MN_%s\n", OpList[Op[n]].Id);
#endif
}

char *SpecTab0[] = { "WAIT", "ORG", "DD", "DW", "DB" };
char *SpecTab1[] = { "LOCKREP", "SEG" };

// Print everything onto the file.
void PutTables(FILE *ExF) {
   if (Ops == 0) Fatal("No assembler mnemonics!");
// Sort the mnemonics alphabetically.
   OpBase = SortOp(OpList, Ops);
   if (!SortOps) {
      for (int o = 0; o < Ops; o++) OpList[o].Next = &OpList[o + 1];
      OpList[Ops - 1].Next = NULL;
   }
// Print out the banner and the oplists[].
   fprintf(ExF,
      "\n"
      ";; --- This file was generated by MakeTabs.exe.\n"
      "\n"
      ";; --- Operand type lists.\n"
      ";; --- They were read from file Op.key.\n"
      "\n"
      "oplists label byte\n\topl\t;; void - for instructions without operands\n"
   );
   for (int K = 0; K < Keys; K++) {
#if 0
      unsigned char KeySize[4];
      if (KeyDict[K].Key > 0xff) {
         KeySize[0] = (unsigned char)(KeyDict[K].Key >> 8);
         KeySize[1] = (unsigned char)(KeyDict[K].Key&0xff);
         KeySize[2] = '\0';
      } else {
         KeySize[0] = (unsigned char)(KeyDict[K].Key);
         KeySize[1] = '\0';
      }
      fprintf(ExF, "\topl %s, %s\t;; ofs=%03xh\n", KeySize, NameTab[K], OffsetTab[K]);
#else
      fprintf(ExF, "\topl %s\t;; idx=%02u, ofs=%03xh\n", NameTab[K], K + 1, OffsetTab[K]);
#endif
   }
#if 0
   fprintf(ExF, "\nOPLIST_27\tEQU 0%xh\t;; this is the _Db key\n", OffsetTab[LookUpKey('27')->Value]);
   fprintf(ExF, "OPLIST_41\tEQU 0%xh\t;; this is the _ES key\n", OffsetTab[LookUpKey('41')->Value]);
#endif
#if 0
   fprintf(ExF, "\nASMMOD\tEQU %u\n", Keys + 1);
#else
   fprintf(ExF, "\nASMMOD\tEQU opidx\n");
#endif
// Dump out AGroupInf.
   fprintf(ExF,
      "\n"
      ";; --- Assembler: data on groups.\n"
      ";; --- If HiByte == 01, it's a \"0f-prefix\" group.\n"
      "\n"
      "agroups label word\n"
   );
   for (int G = 0; G < AGroups; G++) fprintf(ExF, "\tdw %03xh\t;; %u\n", AGroupInf[G], G);
// Dump out AsmTab.
   fprintf(ExF,
      "\n"
      ";; --- List of assembler mnemonics and data.\n"
      ";; --- variant's 1. argument (=a):\n"
      ";; ---   if a < 0x100: one byte opcode.\n"
      ";; ---   if a >= 0x100 && a < 0x200: two byte \"0f\"-opcode.\n"
      ";; ---   if a >= 0x200 && a < 0x240: fp instruction.\n"
      ";; ---   if a >= 0x240: refers to agroups [macro AGRP() is used].\n"
      ";; --- variant's 2. argument is index into array opindex.\n"
      "\n"
      "mnlist label byte\n"
   );
   int Offset = 0;
   for (OpT Op = OpBase; Op != NULL; Op = Op->Next) {
      Op->Offset = Offset + 2;
      Offset += Op->Len + 2;
      fprintf(ExF, "\tmne %s", Op->Id);
      int I = Op->AsmOffset;
      if (AsmTab[I] == D16A && AsmTab[I + 1] == D32A)
#if 0
         fprintf(ExF, ", ASM_D16\t;; ofs=%04x\n", I);
#else
         fprintf(ExF, ", ASM_D16\t;; ofs=%03xh\n", I);
#endif
      else if (AsmTab[I] >= WaitA)
         fprintf(ExF, ", ASM_%s\t;; ofs=%03xh\n", SpecTab0[AsmTab[I] - WaitA], I);
      else if ((AsmTab[I] == SegA || AsmTab[I] == LockRepA))
         fprintf(ExF, ", ASM_%s, %03xh\t;; ofs=%03xh\n", SpecTab1[AsmTab[I] - LockRepA], AsmTab[I + 1], I);
      else {
         int A = I;
         for (; AsmTab[A] > SegA && AsmTab[A] < WaitA; A++) switch (AsmTab[A]) {
            case AaxA: fprintf(ExF, ", ASM_AAX"); break;
            case D16A: fprintf(ExF, ", ASM_D16"); break;
            case D32A: fprintf(ExF, ", ASM_D32"); break;
         }
         fprintf(ExF, "\t;; ofs=%03xh\n", I);
         for (; A < Asms; ) {
            char CPU[12] = { "" };
            if (AsmTab[A] == 0xff) break;
            char *LockS = "";
            if (AsmTab[A] == LockableA) LockS = "ASM_LOCKABLE", A++;
         // There's a problem with dec and inc!
            if (AsmTab[A] == 0xff) break;
            else if (AsmTab[A] >= Mach0A && AsmTab[A] <= Mach6A) sprintf(CPU, "ASM_MACH%u", AsmTab[A++] - Mach0A);
            unsigned K = (int)AsmTab[A]*0x100 + AsmTab[A + 1], L = K%(Keys + 1);
            K /= Keys + 1;
            fprintf(ExF, "\t %s ", K >= 0330 && K < 0340? "fpvariant": "variant");
            if (K >= 0x240) fprintf(ExF, "AGRP(%u,%u), %u", (K - 0x240) >> 3, (K - 0x240)&7, L);
            else fprintf(ExF, "%03xh, %u", K, L);
            A += 2;
            if (K >= 0330 && K < 0340) fprintf(ExF, ", %03xh", AsmTab[A++]);
            if (*CPU != '\0') fprintf(ExF, ", %s, %s\n", LockS, CPU);
            else if (*LockS != '\0') fprintf(ExF, ", %s\n", LockS);
            else putc('\n', ExF);
         }
         fprintf(ExF, "\t endvariant\n");
         I = A;
      }
   }
   fprintf(ExF, "\nend_mnlist label byte\n\n");
   if (Offset >= (1 << ShiftM)) fprintf(stderr, "%d bytes of mnemonics. That's too many.\n", Offset), exit(EXIT_FAILURE);
   char *AuxS;
#if 0
// Print the opindex array.
   AuxS =
      "\n"
      ";; --- Array of byte offsets for the oplists array (above).\n"
      ";; --- It is used by the assembler to save space.\n"
      "\n"
      "opindex label byte\n"
      "\tdb   0,";
   for (int K = 1; K <= Keys; K++) fprintf(ExF, "%s%3d", AuxS, OffsetTab[K - 1] - OPTYPES), AuxS = (K&7) == 7? "\n\tdb ": ",";
#endif
// Print out OpType[].
   fprintf(ExF,
      ";; --- Disassembler: compressed table of the opcode types.\n"
      ";; --- If the item has the format OT(xx), it refers to table 'oplists'.\n"
      ";; --- Otherwise it's an offset for internal table 'disjmp'.\n"
      "\n"
      "optypes label byte"
   );
   AuxS = "\n\tdb ";
   struct InfoRec *TabP = CommentTab;
   for (int I = 0; I < SPARSE_BASE; I += 8) {
      for (int J = 0; J < 8; J++) {
         fputs(AuxS, ExF);
         if (OpType[I + J] >= OPTYPES) {
            int K = 0;
            if (OpType[I + J] > OPTYPES) for (K = 1; K <= Keys; K++) if (OffsetTab[K - 1] == OpType[I + J]) break;
            if (K <= Keys) fprintf(ExF, "OT(%02X)", K); else Fatal("offset not found for %u: %x", I + J, OpType[I + J]);
         } else fprintf(ExF, "  %03xh", OpType[I + J]);
         AuxS = ",";
      }
      fprintf(ExF, "\t;; %02x - %02x", I, I + 7);
      if (I == TabP->Seq) fprintf(ExF, " (%s)", (TabP++)->Id);
      AuxS = "\n\tdb ";
   }
   fprintf(ExF, "\nSPARSE_BASE\tequ $ - optypes\n");
   AuxS =
      "\n"
      ";; --- The rest of these are squeezed.\n"
      "\tdb      0,";
   for (int I = SPARSE_BASE, X = 1; I < NOPS; I++) {
      int J = OpType[I]; if (J == 0) continue;
      int K = 0;
      if (J >= OPTYPES) {
         int K = 0;
         if (J > OPTYPES) for (K = 1; K <= Keys; K++) if (OffsetTab[K - 1] == J) break;
         if (K <= Keys) fprintf(ExF, "%sOT(%02X)", AuxS, K); else Fatal("offset not found for %u: %x", I, J);
      } else fprintf(ExF, "%s  %03xh", AuxS, J);
      X++;
      if ((X&7) == 0) fprintf(ExF, "\t;; %02x", X - 8), AuxS = "\n\tdb "; else AuxS = ",";
   }
   putc('\n', ExF);
// Print out OpInfo[].
   putc('\n', ExF);
   for (int I = 1; I < 7; I++) fprintf(ExF, "P%u86\tequ %xh\n", I, I << ShiftM);
   fprintf(ExF,
      "\n"
      "\talign 2\n"
      "\n"
      ";; --- Disassembler: compressed table of additional information.\n"
      ";; --- Bits 0-11 usually are the offset of the mnemonics table.\n"
      ";; --- Bits 12-15 are the cpu which introduced this opcode.\n"
      "\n"
      "opinfo label word\n"
   );
   for (int I = 0; I < SPARSE_BASE; I += 4) {
      AuxS = "\tdw ";
      for (int J = 0; J < 4; J++) {
         fputs(AuxS, ExF);
         if (OpCPU[I + J]) fprintf(ExF, " P%u86 +", OpCPU[I + J]);
         if (OpType[I + J] >= OPTYPES) fprintf(ExF, " MN_%s", OpList[OpInfo[I + J]].Id);
         else fprintf(ExF, " %04xh", OpInfo[I + J]);
         AuxS = ",";
      }
      fprintf(ExF, "\t;; %02x\n", I);
   }
   AuxS =
      ";; --- The rest of these are squeezed.\n"
      "\tdw  0,";
   for (int I = SPARSE_BASE, X = 1; I < NOPS; I++) {
      int J = OpType[I]; if (J == 0) continue;
      fprintf(ExF, AuxS);
      if (OpCPU[I]) fprintf(ExF, " P%u86 +", OpCPU[I]);
      if (J >= OPTYPES) fprintf(ExF, " MN_%s", OpList[OpInfo[I]].Id); else fprintf(ExF, " %04xh", OpInfo[I]);
      X++;
      if ((X&3) == 0) fprintf(ExF, "\t;; %02x", X - 4), AuxS = "\n\tdw "; else AuxS = ",";
   }
   putc('\n', ExF);
// Print out sqztab.
   fprintf(ExF,
      "\n"
      ";; --- Disassembler: table converts unsqueezed numbers to squeezed.\n"
      ";; --- 1e0-2df are extended opcodes (0f xx).\n"
      "\n"
      "sqztab label byte\n"
   );
   for (int I = SPARSE_BASE, X = 0; I < NOPS; I += 8) {
      if (I == SPARSE_BASE + 0x100) fprintf(ExF, "\n;; --- %u sparse groups\n\n", NSGROUPS);
      else if (I == SPARSE_BASE + 0x100 + 010*NSGROUPS) {
         fprintf(ExF, "\n;; --- %u sparse fpu groups\n\n", Members(SpFpGroupTab));
         fprintf(ExF, "SFPGROUPS equ SPARSE_BASE + ($ - sqztab)\n");
         fprintf(ExF, "SFPGROUP3 equ SFPGROUPS + 8*3\n");
      }
      AuxS = "\tdb ";
      for (int J = 0; J < 8; J++) fprintf(ExF, "%s%3d", AuxS, OpType[I + J] == 0? 0: ++X), AuxS = ",";
      fprintf(ExF, "\t;; %x\n", I);
   }
// Print out the cleanup tables.
   fprintf(ExF,
      "\n"
      ";; --- Disassembler: table of mnemonics that change in the presence of a WAIT\n"
      ";; --- instruction.\n"
      "\n"
   );
   PutPairs(ExF, "wtab", StarSeq, StarOp, Stars);
   fprintf(ExF,
      "N_WTAB\tequ ($ - wtab2)/2\n"
      "\n"
      ";; --- Disassembler: table for operands which have a different mnemonic for\n"
      ";; --- their 32 bit versions (66h prefix).\n"
      "\n"
   );
   PutPairs(ExF, "ltabo", SlashSeq, SlashOp, Slashes);
   fprintf(ExF,
      "N_LTABO\tequ ($ - ltabo2)/2\n"
      "\n"
      ";; --- Disassembler: table for operands which have a different mnemonic for\n"
      ";; --- their 32 bit versions (67h prefix).\n"
      "\n"
   );
   PutPairs(ExF, "ltaba", HashSeq, HashOp, Hashes);
   fprintf(ExF,
      "N_LTABA\tequ ($ - ltaba2)/2\n"
      "\n"
      ";; --- Disassembler: table of lockable instructions\n"
      "\n"
   );
   PutDw(ExF, "locktab label word\n", LockTab, Locks);
   fprintf(ExF, "N_LOCK\tequ ($ - locktab)/2\n");
}

// Read and process files Op.key, Op.ord, Op.set and then dump DebugTab.inc.
int main(void) {
// Read in the key dictionary.
   FILE *KeyF = OpenRead("Op.key");
   int Offset = OPTYPES + 1;
   while (GetLine(KeyF)) {
      char *S = LineBuf, *EndS = strchr(S, ';');
      if (EndS != NULL) do *EndS-- = '\0'; while (EndS > S && (*EndS == ' ' || *EndS == '\t'));
      if (KeyN >= TypeMax) Fatal("Too many keys.");
      KeyDict[KeyN].Key = GetKey(&S);
      S = SpaceOver(S);
      int K = 0;
      for (; ; K++) {
         if (K >= Keys) {
            char *Name = Allocate(strlen(S) + 1, "operand type name");
            strcpy(Name, S);
            if (Keys >= TypeMax) Fatal("Too many operand list types.");
            NameTab[Keys] = Name, OffsetTab[Keys] = Offset++;
            while ((Name = strchr(Name, ',')) != NULL) Name++, Offset++;
            Keys++, Offset++;
         }
         if (strcmp(S, NameTab[K]) == 0) break;
      }
      KeyDict[KeyN].Value = K,
      KeyDict[KeyN].Width =
        strstr(S, "_Ax") != NULL || strstr(S, "_Ex") != NULL || strstr(S, "_Ix") != NULL ||
        strstr(S, "_Ox") != NULL || strstr(S, "_Rx") != NULL? 2:
        strstr(S, "_rb") != NULL || strstr(S, "_rv") != NULL || strstr(S, "_rw") != NULL || strstr(S, "_rd") != NULL? 8: 1;
      KeyN++;
   }
   fclose(KeyF);
   if (Offset >= 0x100) { fprintf(stderr, "%d bytes of operand lists. That's too many.\n", Offset); return EXIT_FAILURE; }
// Read in the ordering relations.
   FILE *OrdF = OpenRead("Op.ord");
   while (GetLine(OrdF)) {
      char *S = LineBuf;
      if (Ords >= OrdMax) Fatal("Too many ordering restrictions.");
      Ord0[Ords] = FindKey(&S);
      S = SpaceOver(S);
      Ord1[Ords] = FindKey(&S);
      if (*S != '\0') Fatal("Syntax error in ordering file.");
      Ords++;
   }
   fclose(OrdF);
// Do the main processing.
   FILE *SetF = OpenRead("Op.set");
   GetOps(SetF), fclose(SetF);
// Write the file.
   FILE *ExF = fopen("DebugTab.inc", "w"); if (ExF == NULL) { perror("DebugTab.inc"); return EXIT_FAILURE; }
   PutTables(ExF), fclose(ExF);
   puts("Done.");
   return EXIT_SUCCESS;
}

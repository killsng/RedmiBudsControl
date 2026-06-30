// auth_helper.c — self-contained Xiaomi auth oracle.
// Emulates libxm_bluetooth.so::function_xiaomi via Unicorn (static link).
// Usage: auth_helper <challenge_hex_32> <libxm_bluetooth.so path>
// Prints: 32-hex-char response.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unicorn/unicorn.h>
#include <unicorn/arm64.h>

typedef struct { uint8_t e_ident[16]; uint16_t e_type,e_machine; uint32_t e_version; uint64_t e_entry,e_phoff,e_shoff; uint32_t e_flags; uint16_t e_ehsize,e_phentsize,e_phnum,e_shentsize,e_shnum,e_shstrndx; } Ehdr;
typedef struct { uint32_t p_type,p_flags; uint64_t p_offset,p_vaddr,p_paddr,p_filesz,p_memsz,p_align; } Phdr;
typedef struct { uint32_t sh_name,sh_type; uint64_t sh_flags,sh_addr,sh_offset,sh_size; uint32_t sh_link,sh_info; uint64_t sh_addralign,sh_entsize; } Shdr;
typedef struct { uint64_t r_offset,r_info; int64_t r_addend; } Rela;
typedef struct { uint32_t st_name; uint8_t st_info,st_other; uint16_t st_shndx; uint64_t st_value, st_size; } Sym;

static uint8_t *filebuf;
static uc_engine *uc;
static uint64_t heap_ptr = 0x70000000;
#define EXT_MALLOC 0x90000000ULL
#define EXT_FREE 0x90000004ULL
#define EXT_RAND 0x90000008ULL
#define EXT_STACKCHK 0x9000000CULL
#define EXT_LOG 0x90000010ULL
#define EXT_MEMSET 0x90000014ULL
#define EXT_CXAFIN 0x90000018ULL
#define EXT_CXAATEX 0x9000001CULL

static void hook_code(uc_engine *u, uint64_t addr, uint32_t sz, void *ud) {
    uint64_t lr; uc_reg_read(u, UC_ARM64_REG_LR, &lr);
    if (addr == EXT_MALLOC) {
        uint64_t n; uc_reg_read(u, UC_ARM64_REG_X0, &n);
        n = (n + 15) & ~15ULL;
        uint64_t p = heap_ptr; heap_ptr += n;
        uc_reg_write(u, UC_ARM64_REG_X0, &p);
    } else if (addr == EXT_MEMSET) {
        uint64_t dst,v,n; uc_reg_read(u,UC_ARM64_REG_X0,&dst); uc_reg_read(u,UC_ARM64_REG_X1,&v); uc_reg_read(u,UC_ARM64_REG_X2,&n);
        if (n && n < 0x100000) { uint8_t b=(uint8_t)v; uint8_t *t=malloc(n); memset(t,b,n); uc_mem_write(u,dst,t,n); free(t); }
        uc_reg_write(u,UC_ARM64_REG_X0,&dst);
    } else if (addr == EXT_RAND) { uint64_t r=0x42424242; uc_reg_write(u,UC_ARM64_REG_X0,&r); }
    uc_reg_write(u, UC_ARM64_REG_PC, &lr);
}

static void map_region(uint64_t start, size_t size) {
    uint64_t page=0x1000, s=start & ~(page-1), e=(start+size+page-1) & ~(page-1);
    uc_mem_map(uc, s, e-s, UC_PROT_ALL);
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr,"usage: %s <hex32> <so>\n", argv[0]); return 2; }
    uint8_t inp[16]; memset(inp,0,16);
    const char *h = argv[1];
    for (int i=0;i<16 && h[2*i] && h[2*i+1]; i++) { char t[3]={h[2*i],h[2*i+1],0}; inp[i]=(uint8_t)strtoul(t,NULL,16); }
    FILE *f=fopen(argv[2],"rb"); if(!f){perror("so");return 2;}
    fseek(f,0,SEEK_END); long fl=ftell(f); fseek(f,0,SEEK_SET); filebuf=malloc(fl); fread(filebuf,1,fl,f); fclose(f);

    Ehdr *eh=(Ehdr*)filebuf; Phdr *ph=(Phdr*)&filebuf[eh->e_phoff];
    uc_open(UC_ARCH_ARM64, UC_MODE_ARM, &uc);
    for (int i=0;i<eh->e_phnum;i++) if (ph[i].p_type==1) { map_region(ph[i].p_vaddr, ph[i].p_memsz); uc_mem_write(uc, ph[i].p_vaddr, &filebuf[ph[i].p_offset], ph[i].p_filesz); }

    Shdr *sh=(Shdr*)&filebuf[eh->e_shoff]; const char *strtab=(const char*)&filebuf[sh[eh->e_shstrndx].sh_offset];
    Shdr *rela_dyn=NULL,*rela_plt=NULL,*dynsym_sh=NULL,*dynstr_sh=NULL;
    for (int i=0;i<eh->e_shnum;i++) { const char *nm=strtab+sh[i].sh_name;
        if (!strcmp(nm,".rela.dyn")) rela_dyn=&sh[i]; else if (!strcmp(nm,".rela.plt")) rela_plt=&sh[i];
        else if (!strcmp(nm,".dynsym")) dynsym_sh=&sh[i]; else if (!strcmp(nm,".dynstr")) dynstr_sh=&sh[i]; }
    Sym *dynsym = dynsym_sh ? (Sym*)&filebuf[dynsym_sh->sh_offset] : NULL;
    const char *dynstr = dynstr_sh ? (const char*)&filebuf[dynstr_sh->sh_offset] : "";

    Shdr *rels[2]={rela_dyn,rela_plt};
    for (int r=0;r<2;r++){ Shdr *rs=rels[r]; if(!rs) continue; Rela *rr=(Rela*)&filebuf[rs->sh_offset]; size_t cnt=rs->sh_size/sizeof(Rela);
        for (size_t i=0;i<cnt;i++){ uint64_t off=rr[i].r_offset; uint32_t type=(uint32_t)(rr[i].r_info&0xffffffff); uint32_t si=(uint32_t)(rr[i].r_info>>32);
            if (type==1027){ uint64_t v=(uint64_t)rr[i].r_addend; uc_mem_write(uc,off,&v,8); }
            else if (type==1026||type==1025||type==257){ const char *nm=dynstr+dynsym[si].st_name; uint64_t val=0;
                if (dynsym[si].st_value) val=dynsym[si].st_value;
                else if (!strcmp(nm,"malloc")) val=EXT_MALLOC; else if (!strcmp(nm,"free")) val=EXT_FREE;
                else if (!strcmp(nm,"rand")) val=EXT_RAND; else if (!strcmp(nm,"__stack_chk_fail")) val=EXT_STACKCHK;
                else if (!strcmp(nm,"__android_log_print")) val=EXT_LOG; else if (!strcmp(nm,"memset")) val=EXT_MEMSET;
                else if (!strcmp(nm,"__cxa_finalize")) val=EXT_CXAFIN; else if (!strcmp(nm,"__cxa_atexit")) val=EXT_CXAATEX;
                if (val) uc_mem_write(uc,off,&val,8);
            } } }

    map_region(0x70000000,0x100000); map_region(0x60000000,0x10000); map_region(0x50000000,0x10000);
    map_region(0x40000000,0x10000); map_region(0x40001000,0x10000); map_region(0x30000000,0x10000); map_region(0x90000000,0x1000);
    uint32_t nop=0xD503201F; for (int i=0;i<16;i++) uc_mem_write(uc,0x90000000+i*4,&nop,4);
    uint64_t canary=0xBEBAFECAULL; uc_mem_write(uc,0x50000000+0x28,&canary,8);

    uc_hook hk; uc_hook_add(uc,&hk,UC_HOOK_CODE,hook_code,NULL,EXT_MALLOC,EXT_CXAATEX+4);
    uc_mem_write(uc,0x40000000,inp,16);
    uint64_t x0=0x130A8,x1=0x40000000,x2=0x13098,x3=0x40001000,sp=0x60008000,tpidr=0x50000000,lr=0x30000000;
    uc_reg_write(uc,UC_ARM64_REG_X0,&x0); uc_reg_write(uc,UC_ARM64_REG_X1,&x1); uc_reg_write(uc,UC_ARM64_REG_X2,&x2); uc_reg_write(uc,UC_ARM64_REG_X3,&x3);
    uc_reg_write(uc,UC_ARM64_REG_SP,&sp); uc_reg_write(uc,UC_ARM64_REG_TPIDR_EL0,&tpidr); uc_reg_write(uc,UC_ARM64_REG_LR,&lr);
    uc_err e=uc_emu_start(uc,0x1770,0x30000000,5*1000000,0);
    if (e){ uint64_t pc; uc_reg_read(uc,UC_ARM64_REG_PC,&pc); fprintf(stderr,"emu error: %s @0x%llx\n",uc_strerror(e),(unsigned long long)pc); return 1; }
    uint8_t out[16]; uc_mem_read(uc,0x40001000,out,16);
    for (int i=0;i<16;i++) printf("%02x",out[i]); printf("\n");
    return 0;
}

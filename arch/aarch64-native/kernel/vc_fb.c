/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: VideoCore mailbox framebuffer + boot console for BCM2711.
          Ported from arch/arm-raspi/boot/vc_fb.c, vc_mb.c, bc/screen_fb.c.
          Runs in the kernel (not bootstrap) so boot messages appear on HDMI.
*/

#include <stdint.h>
#include <string.h>

/* Forward declarations for early UART (kernel_cstart.c) */
extern void uart_puts(const char *s);
extern void uart_puthex(uint64_t val);

/* ---- Mailbox registers (BCM2711) ---- */

#define VCMB_BASE       0xFE00B880UL
#define VCMB_READ       0x00
#define VCMB_STATUS     0x18
#define VCMB_WRITE      0x20
#define VCMB_STATUS_READREADY   (1u << 30)
#define VCMB_STATUS_WRITEREADY  (1u << 31)
#define VCMB_PROPCHAN   8

/* ---- Mailbox property tags ---- */

#define VCTAG_REQ       0x00000000
#define VCTAG_RESP      0x80000000
#define VCTAG_GETRES    0x00040003
#define VCTAG_SETRES    0x00048003
#define VCTAG_SETVRES   0x00048004
#define VCTAG_SETDEPTH  0x00048005
#define VCTAG_FBALLOC   0x00040001
#define VCTAG_GETPITCH  0x00040008

/* ---- MMIO ---- */

static inline void wr32(unsigned long addr, uint32_t val)
{
    __asm__ volatile("dsb sy" ::: "memory");
    *(volatile uint32_t *)addr = val;
}

static inline uint32_t rd32(unsigned long addr)
{
    uint32_t val = *(volatile uint32_t *)addr;
    __asm__ volatile("dmb sy" ::: "memory");
    return val;
}

/* ---- Mailbox read/write ---- */

static volatile uint32_t *vcmb_read(unsigned int chan)
{
    uint32_t msg;
    unsigned int tries = 0x2000000;

    while (tries--)
    {
        while (rd32(VCMB_BASE + VCMB_STATUS) & VCMB_STATUS_READREADY)
        {
            __asm__ volatile("dsb sy");
            if (--tries == 0) return (volatile uint32_t *)0;
        }
        __asm__ volatile("dmb sy");
        msg = rd32(VCMB_BASE + VCMB_READ);
        __asm__ volatile("dmb sy");
        if ((msg & 0xF) == chan)
            return (volatile uint32_t *)(uintptr_t)(msg & ~0xF);
    }
    return (volatile uint32_t *)0;
}

static void vcmb_write(unsigned int chan, void *msg)
{
    while (rd32(VCMB_BASE + VCMB_STATUS) & VCMB_STATUS_WRITEREADY)
        __asm__ volatile("dsb sy");
    __asm__ volatile("dmb sy");
    wr32(VCMB_BASE + VCMB_WRITE, (uint32_t)((uintptr_t)msg & 0xFFFFFFFF) | chan);
}

/* ---- Font (8x14, 256 chars) ---- */

extern const unsigned char fontData[256][14];
#define FONT_W 8
#define FONT_H 14

/* ---- Framebuffer state ---- */

static void     *fb_base;
static uint32_t  fb_width, fb_height, fb_depth, fb_pitch;
static uint32_t  fb_bpp;       /* bytes per pixel */
static uint32_t  con_cols, con_rows;
static uint32_t  con_x, con_y;
static char     *fb_mirror;

/* Static mirror buffer — enough for 1920x1080 / 8x14 = 240x77 = 18480 chars */
static char mirror_buf[240 * 80];

/* ---- Rendering ---- */

static void render_char(unsigned char c, unsigned int xc, unsigned int yc)
{
    const unsigned char *glyph = fontData[c ? c : ' '];
    uint8_t *ptr = (uint8_t *)fb_base + fb_pitch * yc * FONT_H + fb_bpp * xc * FONT_W;

    if (fb_mirror)
        fb_mirror[con_cols * yc + xc] = c;

    for (unsigned int y = 0; y < FONT_H; y++)
    {
        unsigned char bits = glyph[y];
        uint8_t *p = ptr;
        for (unsigned int x = 0; x < FONT_W; x++)
        {
            uint32_t val = (bits & 0x80) ? 0xFFFFFFFF : 0;
            switch (fb_bpp)
            {
            case 4: *(uint32_t *)p = val; break;
            case 2: *(uint16_t *)p = (uint16_t)val; break;
            }
            p += fb_bpp;
            bits <<= 1;
        }
        ptr += fb_pitch;
    }
}

static unsigned int line_len(const char *s)
{
    unsigned int len;
    for (len = 0; len < con_cols; len++)
        if (s[len] == 0) break;
    return len;
}

/* ---- Public API ---- */

void fb_Putc(char chr)
{
    if (chr == 0) return;

    if (chr == 0xFF)
    {
        /* Clear screen */
        memset(fb_base, 0, fb_pitch * fb_height);
        if (fb_mirror) memset(fb_mirror, 0, con_cols * con_rows);
        con_x = con_y = 0;
        return;
    }

    if (chr == '\n' || con_x >= con_cols)
    {
        con_x = 0;
        con_y++;
    }

    if (con_y >= con_rows)
    {
        con_y = con_rows - 1;
        if (fb_mirror)
        {
            unsigned int destLen = line_len(fb_mirror);
            char *src = fb_mirror + con_cols;
            for (unsigned int yc = 0; yc < con_y; yc++)
            {
                unsigned int srcLen = line_len(src);
                unsigned int maxLen = srcLen > destLen ? srcLen : destLen;
                for (unsigned int xc = 0; xc < maxLen; xc++)
                    render_char(src[xc], xc, yc);
                src += con_cols;
                destLen = srcLen;
            }
            for (unsigned int xc = 0; xc < destLen; xc++)
                render_char(0, xc, con_y);
        }
        else
        {
            memmove(fb_base, (uint8_t *)fb_base + fb_pitch * FONT_H,
                    fb_pitch * (fb_height - FONT_H));
            memset((uint8_t *)fb_base + fb_pitch * (fb_height - FONT_H),
                   0, fb_pitch * FONT_H);
        }
    }

    if (chr == '\n') return;

    render_char(chr, con_x++, con_y);
}

/*
 * vcfb_init — allocate framebuffer via VideoCore mailbox.
 * Returns 1 on success, 0 on failure.
 * On success, fb_Putc() can be used for text output.
 */
int vcfb_init(void)
{
    /* 16-byte aligned message buffer */
    static uint32_t __attribute__((aligned(16))) msg[32];
    volatile uint32_t *resp;
    uint32_t w = 0, h = 0;

    uart_puts("[FB] Querying display...\n");

    /* Query display resolution */
    msg[0] = 8 * 4;
    msg[1] = VCTAG_REQ;
    msg[2] = VCTAG_GETRES;
    msg[3] = 8;
    msg[4] = 0;
    msg[5] = 0;
    msg[6] = 0;
    msg[7] = 0;

    vcmb_write(VCMB_PROPCHAN, (void *)msg);
    resp = vcmb_read(VCMB_PROPCHAN);

    if (resp && resp[1] == VCTAG_RESP)
    {
        w = resp[5];
        h = resp[6];
    }
    if (w == 0 || h == 0)
    {
        w = 1280;
        h = 720;
    }

    uart_puts("[FB] Resolution: ");
    uart_puthex(w);
    uart_puts("x");
    uart_puthex(h);
    uart_puts("\n");

    /* Allocate framebuffer: set res, vres, depth, alloc */
    {
        unsigned int c = 1;
        msg[c++] = VCTAG_REQ;

        msg[c++] = VCTAG_SETRES;
        msg[c++] = 8; msg[c++] = 0;
        msg[c++] = w; msg[c++] = h;

        msg[c++] = VCTAG_SETVRES;
        msg[c++] = 8; msg[c++] = 0;
        msg[c++] = w; msg[c++] = h;

        msg[c++] = VCTAG_SETDEPTH;
        msg[c++] = 4; msg[c++] = 0;
        msg[c++] = 32;  /* 32bpp */

        msg[c++] = VCTAG_FBALLOC;
        msg[c++] = 8; msg[c++] = 0;
        msg[c++] = 16;  /* alignment */
        msg[c++] = 0;

        msg[c++] = 0;   /* end tag */
        msg[0] = c * 4;

        vcmb_write(VCMB_PROPCHAN, (void *)msg);
        resp = vcmb_read(VCMB_PROPCHAN);

        if (!resp || resp[1] != VCTAG_RESP)
        {
            uart_puts("[FB] Alloc failed\n");
            return 0;
        }

        /* Find FBALLOC response */
        unsigned int i = 2;
        while (resp[i])
        {
            if (resp[i] == VCTAG_FBALLOC) break;
            i += 3 + (resp[i + 1] >> 2);
            if (i > c) { uart_puts("[FB] FBALLOC not found\n"); return 0; }
        }

        if ((resp[i + 2] & 0x7FFFFFFF) != 8)
        {
            uart_puts("[FB] FBALLOC bad response\n");
            return 0;
        }

        fb_base = (void *)(uintptr_t)(resp[i + 3] & 0x3FFFFFFF);
        if (!fb_base || resp[i + 4] == 0)
        {
            uart_puts("[FB] No framebuffer\n");
            return 0;
        }
    }

    /* Query pitch */
    msg[0] = 7 * 4;
    msg[1] = VCTAG_REQ;
    msg[2] = VCTAG_GETPITCH;
    msg[3] = 4; msg[4] = 0; msg[5] = 0;
    msg[6] = 0;

    vcmb_write(VCMB_PROPCHAN, (void *)msg);
    resp = vcmb_read(VCMB_PROPCHAN);

    if (!resp || (resp[4] & 0x7FFFFFFF) != 4 || resp[5] == 0)
    {
        uart_puts("[FB] Pitch query failed\n");
        return 0;
    }

    fb_width = w;
    fb_height = h;
    fb_depth = 32;
    fb_pitch = resp[5];
    fb_bpp = fb_depth >> 3;

    con_cols = fb_width / FONT_W;
    con_rows = fb_height / FONT_H;
    con_x = con_y = 0;

    /* Set up mirror buffer */
    if (con_cols * con_rows <= (int)sizeof(mirror_buf))
    {
        fb_mirror = mirror_buf;
        memset(fb_mirror, 0, con_cols * con_rows);
    }
    else
        fb_mirror = (char *)0;

    /* Clear framebuffer */
    memset(fb_base, 0, fb_pitch * fb_height);

    uart_puts("[FB] OK: ");
    uart_puthex(fb_width);
    uart_puts("x");
    uart_puthex(fb_height);
    uart_puts("x");
    uart_puthex(fb_depth);
    uart_puts(" @ ");
    uart_puthex((uint64_t)(uintptr_t)fb_base);
    uart_puts(" pitch=");
    uart_puthex(fb_pitch);
    uart_puts("\n");

    return 1;
}

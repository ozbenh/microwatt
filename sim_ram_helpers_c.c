#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <endian.h>
#include <errno.h>
#include "sim_vhpi_c.h"

//#define DEBUG

struct ram_block {
	unsigned int width;   /* In bytes */
	unsigned int rows;    /* In rows */
	unsigned long total_size;
	void *m;
};

#define MAX_BLOCKS 128
static struct ram_block ram_blocks[MAX_BLOCKS];
static unsigned int block_count;

#ifdef DEBUG
#define DBG(fmt...) do { printf(fmt); } while(0)
#else
#define DBG(fmt...) do {} while(0)
#endif

int ram_create(unsigned int width, unsigned int size)
{
	struct ram_block *r;

	DBG("%s: width=%d, size=%d\n", __func__, width, size);

	if (block_count == MAX_BLOCKS) {
		fprintf(stderr, "%s: too many blocks, bump MAX_BLOCKS\n", __func__);
		return -1;
	}
	r = &ram_blocks[block_count];
	r->width = width;
	r->rows = size;
	r->total_size = ((unsigned long)width) * size;
	r->m = malloc(r->total_size);
	DBG("%s: allocating %ld bytes\n", __func__, r->total_size);
	if (!r->m) {
		fprintf(stderr, "%s: failed to allocate %ld bytes\n", __func__,
			(long)r->total_size);
		return -1;
	}
	memset(r->m, 0, r->total_size);
	DBG("%s: returning %d\n", __func__, block_count);
	return block_count++;
}

static int load_hex_file(struct ram_block *r, unsigned int row, const char *name)
{
	unsigned long offset;
	unsigned long long val;
	unsigned int i;
	FILE *f;
	ssize_t rc, lw;
	size_t len;
	char *line = NULL;
	unsigned char *p, *endp;

	f = fopen(name, "r");
	if (!f) {
		fprintf(stderr, "%s: Failed to open %s, %s\n", __func__,
			name, strerror(errno));
		return -1;
	}

	/* Now we check the first line to verify the size */
	rc = getline(&line, &len, f);
	if (rc < -1) {
		fprintf(stderr, "%s: Failed to read first line of %s\n", __func__,
			name);
		fclose(f);
		return -1;
	}

	/* Now deduce if it's a 32-bit or 64-bit wide file. We could sanity check
	 * mode but this will do for now
	 */
	if (rc < 16)
		lw = 4;
	else
		lw = 8;
	offset = ((unsigned long)row) * r->width;
	p = r->m + offset;
	endp = r->m + r->total_size;

	for (;;) {
		/* Process line */
		val = strtoull(line, NULL, 16);
#if __BYTE_ORDER == __BIG_ENDIAN
#error Fix big endian support -> add byteswap
#endif
		for (i = 0; i < lw && p < endp; i++) {
			*(p++) = val & 0xff;
			val >>= 8;

		}
		rc = getline(&line, &len, f);
		if (rc < lw)
			break;
		if (p == endp) {
			fprintf(stderr, "%s: File %s bigger than available memory, cropping\n",
				__func__, name);
			break;
		}
	}
	free(line);
	fclose(f);

	return 0;
}

static int load_bin_file(struct ram_block *r, unsigned int row, const char *name)
{
	unsigned long offset, size;
	size_t sr;
	struct stat sbuf;
	FILE *f;
	int rc;

	rc = stat(name, &sbuf);
	if (rc) {
		fprintf(stderr, "%s: Failed to stat %s, %s\n", __func__,
			name, strerror(errno));
		return -1;
	}

	size = sbuf.st_size;
	offset = ((unsigned long)row) * r->width;
	if ((offset + size) > r->total_size) {
		fprintf(stderr, "%s: File %s bigger than available memory, cropping\n",
			__func__, name);
		/* Non-fatal, don't return  */
		size = r->total_size - offset;
	}
	f = fopen(name, "r");
	if (!f) {
		fprintf(stderr, "%s: Failed to open %s, %s\n", __func__,
			name, strerror(errno));
		return -1;
	}
	sr = fread(r->m + offset, 1, size, f);
	if (sr < size) {
		fprintf(stderr, "%s: file %s hort read ! wanted %ld got %ld\n",
			__func__, name, size, (unsigned long)sr);
		/* Non-fatal, don't return */
	}
	fclose(f);
	return 0;
}

int ram_load_file(unsigned int block, unsigned int row, void *fname_fp)
{
	struct ram_block *r;
	char *fname;
	int l, rc = 0;

	if (block >= block_count) {
		fprintf(stderr, "%s: block %d out of range (max=%d)\n",
			__func__, block, block_count-1);
		return -1;
	}
	r = &ram_blocks[block];
	if (row >= r->rows) {
		fprintf(stderr, "%s: row %d out of range (max=%d)\n",
			__func__, row, r->rows-1);
		return -1;
	}
	fname = from_string(fname_fp);
	if (!fname)
		return -1;
	l = strlen(fname);
	if (l > 4 && !strcmp(fname + l - 4, ".bin"))
		rc = load_bin_file(r, row, fname);
	else if (l > 4 && !strcmp(fname + l - 4, ".hex"))
		rc = load_hex_file(r, row, fname);
	else {
		rc = -1;
		fprintf(stderr, "%s: unsupported file type %s\n",
			__func__, fname);
	}
	if (rc == 0) {
		DBG("%s: Loaded file %s: %02x %02x %02x %02x\n",
		    __func__, fname,
		    *(unsigned char *)r->m,
		    *(unsigned char *)(r->m + 1),
		    *(unsigned char *)(r->m + 2),
		    *(unsigned char *)(r->m + 3));
	}
	free(fname);
	return rc;
}

void ram_read(unsigned int block, unsigned int row, unsigned char *vec)
{
	unsigned long offset;
	struct ram_block *r;
	unsigned char *p, b;
	int i;

	DBG("%s: block=%d row=%d vec=%p\n", __func__, block, row, vec);

	if (block >= block_count) {
		fprintf(stderr, "%s: block %d out of range (max=%d)\n",
			__func__, block, block_count-1);
		return;
	}
	r = &ram_blocks[block];
	if (row >= r->rows) {
		fprintf(stderr, "%s: row %d out of range (max=%d)\n",
			__func__, row, r->rows-1);
		return;
	}
	offset = ((unsigned long)row) * r->width;
	p = r->m + offset;
	for (i = r->width - 1; i >=0; i--) {
		b = *(p + i);
		*(vec++) = (b & 0x80) ? vhpi1 : vhpi0;
		*(vec++) = (b & 0x40) ? vhpi1 : vhpi0;
		*(vec++) = (b & 0x20) ? vhpi1 : vhpi0;
		*(vec++) = (b & 0x10) ? vhpi1 : vhpi0;
		*(vec++) = (b & 0x08) ? vhpi1 : vhpi0;
		*(vec++) = (b & 0x04) ? vhpi1 : vhpi0;
		*(vec++) = (b & 0x02) ? vhpi1 : vhpi0;
		*(vec++) = (b & 0x01) ? vhpi1 : vhpi0;
	}
}

void ram_write(unsigned int block, unsigned int row, unsigned char *vec,
	       unsigned char *sel)
{
	unsigned long offset;
	struct ram_block *r;
	unsigned char *p, b;
	int i;

	if (block >= block_count) {
		fprintf(stderr, "%s: block %d out of range (max=%d)\n",
			__func__, block, block_count-1);
		return;
	}
	r = &ram_blocks[block];
	if (row >= r->rows) {
		fprintf(stderr, "%s: row %d out of range (max=%d)\n",
			__func__, row, r->rows-1);
		return;
	}
	offset = ((unsigned long)row) * r->width;
	p = r->m + offset;
	for (i = r->width - 1; i >=0; i--) {
		if (*(sel++) != vhpi1) {
			vec += 8;
			continue;
		}
		b = 0;
		b |= *(vec++) == vhpi1 ? 0x80 : 0x00;
		b |= *(vec++) == vhpi1 ? 0x40 : 0x00;
		b |= *(vec++) == vhpi1 ? 0x20 : 0x00;
		b |= *(vec++) == vhpi1 ? 0x10 : 0x00;
		b |= *(vec++) == vhpi1 ? 0x08 : 0x00;
		b |= *(vec++) == vhpi1 ? 0x04 : 0x00;
		b |= *(vec++) == vhpi1 ? 0x02 : 0x00;
		b |= *(vec++) == vhpi1 ? 0x01 : 0x00;
		*(p + i) = b;
	}
}

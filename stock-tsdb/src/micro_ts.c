#include <stdint.h>
#include <string.h>
#include <arpa/inet.h>

// 字节序转换函数兼容性处理
#ifdef __APPLE__
#include <libkern/OSByteOrder.h>
#define htobe16(x) OSSwapHostToBigInt16(x)
#define htobe32(x) OSSwapHostToBigInt32(x)
#define htobe64(x) OSSwapHostToBigInt64(x)
#define be16toh(x) OSSwapBigToHostInt16(x)
#define be32toh(x) OSSwapBigToHostInt32(x)
#define be64toh(x) OSSwapBigToHostInt64(x)
#else
#include <endian.h>
#endif

/* 打包 Key + Qual */
void pack_key_qual(uint8_t *out18,
                   char market, const char *code9,
                   uint64_t chunk_base_ms)
{
    out18[0] = market;
    memcpy(out18+1, code9, 9);              // ASCII 无需转
    chunk_base_ms = htobe64(chunk_base_ms); // 大端
    memcpy(out18+10, &chunk_base_ms, 8);
}

void pack_qual(uint8_t *out6, uint32_t micro_off, uint16_t seq)
{
    micro_off = htobe32(micro_off);
    seq       = htobe16(seq);
    memcpy(out6,   &micro_off, 4);
    memcpy(out6+4, &seq,       2);
}

/* 打包 Value */
void pack_value(uint8_t *out50,
                int32_t price, uint32_t qty,
                uint8_t ch, uint8_t side,
                uint64_t order_no, uint64_t tick_no)
{
    price   = htobe32(price);
    qty     = htobe32(qty);
    order_no = htobe64(order_no);
    tick_no  = htobe64(tick_no);
    memcpy(out50+0,  &price,    4);
    memcpy(out50+4,  &qty,      4);
    out50[8]  = ch;
    out50[9]  = side;
    memcpy(out50+10, &order_no, 8);
    memcpy(out50+18, &tick_no,  8);
    memset(out50+26, 0, 24);   // reserved
}

/* 解包 Value */
void unpack_value(const uint8_t *in50,
                  int32_t *price, uint32_t *qty,
                  uint8_t *ch, uint8_t *side,
                  uint64_t *order_no, uint64_t *tick_no)
{
    memcpy(price,    in50+0,  4); *price    = be32toh(*price);
    memcpy(qty,      in50+4,  4); *qty      = be32toh(*qty);
    *ch     = in50[8];
    *side   = in50[9];
    memcpy(order_no, in50+10, 8); *order_no = be64toh(*order_no);
    memcpy(tick_no,  in50+18, 8); *tick_no  = be64toh(*tick_no);
}

/* 解包时间戳 */
uint64_t unpack_timestamp(const uint8_t *in18)
{
    uint64_t timestamp_ms;
    memcpy(&timestamp_ms, in18+10, 8);
    return be64toh(timestamp_ms);
}
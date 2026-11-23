#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct cr_engine cr_engine;
const char * cr_system_prompt(void);
typedef void (*cr_text_callback)(const char * bytes, size_t count, void * user);
typedef struct {
    double load_seconds;
    double first_token_seconds;
    double total_seconds;
    int32_t prompt_tokens;
    int32_t generated_tokens;
    bool cancelled;
    bool reached_limit;
    bool reasoning_filtered;
    int32_t visible_bytes;
    bool thinking_open_token_suppressed;
    bool constrained_json;
} cr_metrics;
// All model/context operations belong to one serial worker. Only cr_cancel may
// be called concurrently. Never destroy an engine until its generation returns.
cr_engine * cr_create(const char * path, bool metal, char * error, size_t capacity);
int cr_generate(cr_engine *, const char * system, const char * question,
                const char * snapshot, int max_tokens, cr_text_callback, void *,
                cr_metrics *, char * error, size_t capacity);
// Requires an app-owned fact context. Enforces JSON shape and valid fact IDs;
// the caller must still validate and review the generated suggestions.
int cr_generate_contract(cr_engine *, const char * system, const char * question,
                const char * snapshot, int max_tokens, cr_text_callback, void *,
                cr_metrics *, char * error, size_t capacity);
void cr_cancel(cr_engine *);
void cr_prepare(cr_engine *);
void cr_destroy(cr_engine *);
#ifdef __cplusplus
}
#endif

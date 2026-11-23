#pragma once
#include "json.h"
#include "jinja/value.h"
#include "jinja/runtime.h"

inline void cr_set_chat_globals(jinja::context & context, const common_json & input) {
    jinja::global_from_json(context, input, true);
    // Only model-owned control strings are trusted. Message strings remain data.
    const common_json controls{{"bos_token", input.at("bos_token")}, {"eos_token", input.at("eos_token")}};
    jinja::global_from_json(context, controls, false);
}

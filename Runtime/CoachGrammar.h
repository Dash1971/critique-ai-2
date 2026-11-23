#pragma once
#include "json.h"
#include <cctype>
#include <stdexcept>
#include <string>
#include <vector>

// Format/evidence-ID constraints only. Semantic checks remain in CritiqueCore;
// a grammar cannot establish that arbitrary advice is appropriate.
inline std::string cr_coach_grammar(const char * snapshot) {
    auto context = common_json::parse(snapshot);
    const auto & facts = context.at("facts");
    if (!facts.is_array() || facts.empty() || facts.size() > 20) throw std::runtime_error("Invalid fact context");
    std::string ids;
    for (const auto & fact : facts) {
        const auto id = fact.at("id").get<std::string>();
        if (id.empty() || id.size() > 40) throw std::runtime_error("Invalid fact ID");
        for (unsigned char c : id) if (!std::isalnum(c) && c != '_') throw std::runtime_error("Invalid fact ID");
        if (!ids.empty()) ids += " | ";
        ids += common_json(common_json(id).dump()).dump();
    }
    return std::string(R"GBNF(root ::= ws "{" ws response ws "}" ws
response ::= "\"response_kind\"" ws ":" ws "\"facts\"" ws "," ws facts ws "," ws "\"suggestions\"" ws ":" ws "[]" ws "," ws "\"question\"" ws ":" ws "null" | "\"response_kind\"" ws ":" ws "\"plan\"" ws "," ws facts ws "," ws "\"suggestions\"" ws ":" ws "[" ws action (ws "," ws action)? ws "]" ws "," ws "\"question\"" ws ":" ws "null" | "\"response_kind\"" ws ":" ws "\"clarification\"" ws "," ws facts ws "," ws "\"suggestions\"" ws ":" ws "[]" ws "," ws "\"question\"" ws ":" ws question-text
facts ::= "\"fact_ids\"" ws ":" ws "[" ws fact-id (ws "," ws fact-id){0,2} ws "]"
question-text ::= "\"" question-char{1,159} "?\""
question-char ::= [^"\\?\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4})
action ::= "{" ws "\"kind\"" ws ":" ws kind ws "," ws "\"text\"" ws ":" ws action-text (ws "," ws "\"proposed_minutes\"" ws ":" ws minutes)? ws "}"
action-text ::= "\"" verb " " char{1,160} "\""
verb ::= "Consider" | "Try" | "Plan" | "Practice" | "Choose" | "Review" | "Pause" | "Seek" | "Ask" | "Build" | "Keep" | "Focus" | "Create" | "Set" | "Reflect"
kind ::= "\"practice\"" | "\"planning\"" | "\"reflection\"" | "\"recovery\"" | "\"seek_help\""
minutes ::= [1-9] | [1-9] [0-9] | "1" [0-7] [0-9] | "180"
char ::= [^"\\\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4})
ws ::= " "?
fact-id ::= )GBNF") + ids + "\n";
}

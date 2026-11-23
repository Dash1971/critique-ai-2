#pragma once
#include <algorithm>
#include <functional>
#include <string>

// The generation budget still includes hidden tokens. This only separates
// model protocol markup from visible output; it never invents an answer.
class ReasoningFilter {
    std::string pending;
    bool inside = false;
public:
    bool filtered = false;
    size_t visible_bytes = 0;
    void push(const std::string & bytes, const std::function<void(const std::string &)> & emit) {
        pending += bytes;
        const std::string open = "<think>", close = "</think>";
        while (!pending.empty()) {
            const auto a = pending.find(open), b = pending.find(close);
            const auto marker = std::min(a, b);
            if (marker != std::string::npos) {
                if (!inside && marker) { emit(pending.substr(0, marker)); visible_bytes += marker; }
                inside = marker == a; filtered = true;
                pending.erase(0, marker + (inside ? open.size() : close.size()));
                continue;
            }
            size_t keep = 0;
            for (const auto & tag : {open, close}) {
                for (size_t n = 1; n < tag.size() && n <= pending.size(); ++n) {
                    if (pending.compare(pending.size() - n, n, tag, 0, n) == 0) keep = std::max(keep, n);
                }
            }
            const auto ready = pending.size() - keep;
            if (!inside && ready) { emit(pending.substr(0, ready)); visible_bytes += ready; }
            pending.erase(0, ready);
            break;
        }
    }
    bool finish() const { return !inside && pending.empty(); }
};

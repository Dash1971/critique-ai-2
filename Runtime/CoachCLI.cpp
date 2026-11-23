#include "CoachBridge.h"
#include "json.h"
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <string>
#include <fstream>
#include <sstream>
int main(int argc, char ** argv) {
    if (argc < 2) { std::cerr << "Usage: critique-coach MODEL [QUESTION]\n"; return 1; }
    char error[512] = {};
    auto * engine = cr_create(argv[1], false, error, sizeof(error));
    if (!engine) { std::cerr << error << "\n"; return 2; }
    const char * question = argc > 2 ? argv[2] : "Suggest two small improvements based only on these recorded habits.";
    std::string policy_storage;
    const char * system = cr_system_prompt();
    bool structured = false;
    for (int i = 2; i < argc; ++i) if (std::string(argv[i]) == "--contract") structured = true;
    if (argc > 5 && std::string(argv[4]) == "--policy") {
        std::ifstream policy_file(argv[5]);
        if (!policy_file) { std::cerr << "Requested policy file is missing.\n"; cr_destroy(engine); return 3; }
        std::stringstream policy_buffer; policy_buffer << policy_file.rdbuf(); policy_storage = policy_buffer.str();
        if (policy_storage.empty() || policy_storage.size() > 12000) { std::cerr << "Invalid policy file.\n"; cr_destroy(engine); return 3; }
        system = policy_storage.c_str();
    }
    if (argc > 3 && std::string(argv[2]) == "--cases") {
        std::ifstream file(argv[3]); std::stringstream buffer; buffer << file.rdbuf();
        auto corpus = common_json::parse(buffer.str());
        int index = 0;
        for (const auto & item : corpus.at("cases")) {
            cr_prepare(engine);
            std::string output; cr_metrics m{};
            std::string prompt = item.at("question").get<std::string>();
            std::string records = item.at("snapshot").dump();
            auto generate = structured ? cr_generate_contract : cr_generate;
            int code = generate(engine, system, prompt.c_str(), records.c_str(), structured ? 256 : 160,
                [](const char * text, size_t count, void * user) { static_cast<std::string *>(user)->append(text, count); },
                &output, &m, error, sizeof(error));
            common_json row{{"id", item.at("id")}, {"status", code}, {"answer", output},
                {"prompt_tokens", m.prompt_tokens}, {"output_tokens", m.generated_tokens},
                {"generation_seconds", m.total_seconds}, {"first_token_seconds", m.first_token_seconds},
                {"truncated", m.reached_limit}, {"reasoning_filtered", m.reasoning_filtered}, {"visible_bytes", m.visible_bytes},
                {"thinking_open_token_suppressed", m.thinking_open_token_suppressed}, {"constrained_json", m.constrained_json}, {"index", index++}};
            std::cout << row.dump() << std::endl;
        }
        cr_destroy(engine); return 0;
    }
    const char * snapshot = "{\"period\":\"last 7 days\",\"habits\":[{\"title\":\"Read\",\"scheduled\":7,\"completed\":4}],\"focus_minutes\":90,\"workouts\":[],\"missing\":[\"workout history\",\"nutrition\"]}";
    cr_metrics metrics{};
    int status = cr_generate(engine, system, question, snapshot, 160,
        [](const char * p, size_t n, void *) { std::cout.write(p, n); std::cout.flush(); }, nullptr, &metrics, error, sizeof(error));
    std::cout << "\n";
    std::cerr << "load_seconds=" << metrics.load_seconds << " first_token_seconds=" << metrics.first_token_seconds
              << " total_seconds=" << metrics.total_seconds << " prompt_tokens=" << metrics.prompt_tokens
              << " generated_tokens=" << metrics.generated_tokens << " limit=" << metrics.reached_limit << "\n";
    if (status) std::cerr << error << "\n";
    cr_destroy(engine); return status;
}

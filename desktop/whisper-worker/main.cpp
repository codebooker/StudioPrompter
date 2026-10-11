#include "whisper.h"
#include <iostream>
#include <vector>
#include <sstream>
#include <cmath>
#include <cstring>
#include <algorithm>
#include <thread>
#if defined(_MSC_VER) && defined(_M_X64)
#include <intrin.h>
#elif defined(__x86_64__)
#include <cpuid.h>
#endif

// Probe from the baseline binary before ever loading the optimized engine.
// AVX requires OS support for preserving YMM registers as well as CPU support.
static bool supports_avx2() {
#if defined(_MSC_VER) && defined(_M_X64)
    int info[4]; __cpuid(info, 0); if (info[0] < 7) return false;
    __cpuidex(info, 1, 0);
    const unsigned required=(1u<<20)|(1u<<12)|(1u<<27)|(1u<<28)|(1u<<29);
    if ((static_cast<unsigned>(info[2]) & required) != required) return false;
    if ((_xgetbv(0) & 6) != 6) return false;
    __cpuidex(info, 7, 0); return (info[1] & ((1<<5)|(1<<8))) == ((1<<5)|(1<<8));
#elif defined(__x86_64__)
    __builtin_cpu_init();
    return __builtin_cpu_supports("avx2") && __builtin_cpu_supports("fma") && __builtin_cpu_supports("f16c") && __builtin_cpu_supports("bmi2") && __builtin_cpu_supports("sse4.2");
#else
    return false;
#endif
}
#ifdef _WIN32
#include <io.h>
#include <fcntl.h>
#endif

static std::string json(const std::string &text) {
    std::string out="\"";
    for(unsigned char c:text) {
        if(c=='"'||c=='\\') {out+='\\';out+=c;}
        else if(c=='\n')out+="\\n";else if(c=='\r')out+="\\r";else if(c=='\t')out+="\\t";
        else if(c<32) {const char *hex="0123456789abcdef";out+="\\u00";out+=hex[c>>4];out+=hex[c&15];}
        else out+=c;
    }
    return out+'"';
}
static void reply(const std::string &message) {
    const uint32_t size=static_cast<uint32_t>(message.size());
    unsigned char header[4]={static_cast<unsigned char>(size>>24),static_cast<unsigned char>(size>>16),static_cast<unsigned char>(size>>8),static_cast<unsigned char>(size)};
    std::cout.write(reinterpret_cast<char*>(header),4);std::cout.write(message.data(),message.size());std::cout.flush();
}
int main(int argc,char **argv) {
#ifdef _WIN32
    _setmode(_fileno(stdin),_O_BINARY);_setmode(_fileno(stdout),_O_BINARY);
#endif
    if(argc!=2)return 2;
    if(std::strcmp(argv[1],"--capabilities")==0){std::cout<<(supports_avx2()?"avx2":"baseline");return 0;}
    whisper_context_params options=whisper_context_default_params();options.use_gpu=false;
    auto *context=whisper_init_from_file_with_params(argv[1],options);if(!context)return 3;
    while(true) {
        unsigned char header[4];if(!std::cin.read(reinterpret_cast<char*>(header),4))break;
        const uint32_t size=(uint32_t(header[0])<<24)|(uint32_t(header[1])<<16)|(uint32_t(header[2])<<8)|header[3];
        if(size<44||size>320000)break;
        std::vector<unsigned char> wav(size);if(!std::cin.read(reinterpret_cast<char*>(wav.data()),size))break;
        if(std::memcmp(wav.data(),"RIFF",4)||std::memcmp(wav.data()+8,"WAVE",4)||std::memcmp(wav.data()+12,"fmt ",4)||std::memcmp(wav.data()+36,"data",4)||wav[20]!=1||wav[22]!=1||wav[24]!=0x80||wav[25]!=0x3e||wav[34]!=16||(size-44)%2){reply("{\"error\":\"Invalid PCM audio\"}");continue;}
        std::vector<float> samples((size-44)/2);for(size_t i=0;i<samples.size();i++){uint16_t value=uint16_t(wav[44+i*2])|(uint16_t(wav[45+i*2])<<8);samples[i]=static_cast<int16_t>(value)/32768.f;}
        auto params=whisper_full_default_params(WHISPER_SAMPLING_GREEDY);params.language="en";params.n_threads=std::max(1u,std::min(4u,std::thread::hardware_concurrency()));params.no_context=true;params.token_timestamps=true;params.max_tokens=160;params.suppress_blank=true;params.suppress_nst=true;params.temperature_inc=0;params.greedy.best_of=1;params.print_realtime=false;params.print_progress=false;params.print_timestamps=false;
        // A six-second live window does not need the default thirty-second
        // encoder context. Keep ten seconds of context including padding.
        params.audio_ctx=512;
        if(whisper_full(context,params,samples.data(),static_cast<int>(samples.size()))!=0){reply("{\"error\":\"Speech processing failed\"}");continue;}
        std::string text;std::ostringstream tokens;bool first=true;
        for(int segment=0;segment<whisper_full_n_segments(context);segment++) {
            if(whisper_full_get_segment_no_speech_prob(context,segment)>=.65f)continue;
            const int count=whisper_full_n_tokens(context,segment);double logprob=0;int scored=0;
            for(int t=0;t<count;t++)if(whisper_full_get_token_id(context,segment,t)<whisper_token_eot(context)){logprob+=std::log(std::max(.000001f,whisper_full_get_token_p(context,segment,t)));scored++;}
            if(scored==0||logprob/scored < -1.2)continue;
            text+=whisper_full_get_segment_text(context,segment);
            for(int t=0;t<count;t++) {
                if(whisper_full_get_token_id(context,segment,t)>=whisper_token_eot(context))continue;
                auto token=whisper_full_get_token_data(context,segment,t);if(token.p<=.15f)continue;
                if(!first)tokens<<',';first=false;
                const double start=std::max(0.0,token.t0*.01),end=std::max(start,token.t1*.01);
                tokens<<"{\"text\":"<<json(whisper_full_get_token_text(context,segment,t))<<",\"start\":"<<start<<",\"end\":"<<end<<'}';
            }
        }
        reply("{\"text\":"+json(text)+",\"tokens\":["+tokens.str()+"]}");
    }
    whisper_free(context);return 0;
}

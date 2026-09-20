import Foundation
import PrompterCore
import llama

public enum CommandModelError: Error { case unavailable, tooLong, inference, timeout }

/// Serial actor keeps inference off the main thread and owns all llama pointers.
public actor CommandModel {
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    public init() {}
    deinit {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
    }
    public func unload() {
        if let context { llama_free(context) }; context = nil
        if let model { llama_model_free(model) }; model = nil
    }
    public func load(path: String) throws {
        guard model == nil else { return }
        llama_log_set({ _, _, _ in }, nil)
        ggml_log_set({ _, _, _ in }, nil)
        llama_backend_init()
        var params = llama_model_default_params()
        params.n_gpu_layers = 99
        guard let loaded = llama_model_load_from_file(path, params) else { throw CommandModelError.unavailable }
        var config = llama_context_default_params()
        config.n_ctx = 2048; config.n_batch = 1024; config.n_ubatch = 256
        config.n_threads = 2; config.n_threads_batch = 2
        guard let ctx = llama_init_from_model(loaded, config) else {
            llama_model_free(loaded); throw CommandModelError.unavailable
        }
        model = loaded; context = ctx
    }
    public func classify(_ request: String) throws -> String {
        try Task.checkCancellation()
        guard CommandIntent.acceptsRequest(request) else { return "{\"action\":\"unknown\"}" }
        guard request.count <= 300 else { throw CommandModelError.tooLong }
        guard let model, let context, let vocab = llama_model_get_vocab(model) else { throw CommandModelError.unavailable }
        let deadline = ProcessInfo.processInfo.systemUptime + 4
        let prompt = CommandIntent.prompt(for: request)
        var tokens = [llama_token](repeating: 0, count: 2048)
        let count = llama_tokenize(vocab, prompt, Int32(prompt.utf8.count), &tokens, Int32(tokens.count), true, true)
        guard count > 0, count < 1900 else { throw CommandModelError.tooLong }
        llama_memory_clear(llama_get_memory(context), true)
        guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()) else { throw CommandModelError.inference }
        defer { llama_sampler_free(sampler) }
        guard let grammar = llama_sampler_init_grammar(vocab, CommandIntent.grammar(for: request), "root") else { throw CommandModelError.inference }
        llama_sampler_chain_add(sampler, grammar)
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())
        // Split long prompts to respect n_batch; never hand an oversized batch to C.
        var offset = 0
        while offset < Int(count) {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw CommandModelError.timeout }
            let length = min(1024, Int(count) - offset)
            let status = tokens.withUnsafeMutableBufferPointer { buffer in
                llama_decode(context, llama_batch_get_one(buffer.baseAddress!.advanced(by: offset), Int32(length)))
            }
            guard status == 0 else { throw CommandModelError.inference }
            offset += length
        }
        var bytes: [UInt8] = []
        for _ in 0..<32 {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw CommandModelError.timeout }
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { return String(decoding: bytes, as: UTF8.self) }
            var piece = [CChar](repeating: 0, count: 128)
            let length = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
            guard length >= 0, length <= piece.count else { throw CommandModelError.inference }
            bytes.append(contentsOf: piece.prefix(Int(length)).map { UInt8(bitPattern: $0) })
            if bytes.last == 125 { return String(decoding: bytes, as: UTF8.self) }
            guard llama_decode(context, llama_batch_get_one(&token, 1)) == 0 else { throw CommandModelError.inference }
        }
        throw CommandModelError.inference
    }
}

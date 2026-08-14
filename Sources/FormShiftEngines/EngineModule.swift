import FormShiftCore

public enum FormShiftEnginesModule {}

public enum DefaultEngineRegistryFactory {
    public static func makeRegistry() async -> EngineRegistry {
        let registry = EngineRegistry()
        await registry.register(ImageIOEngine())
        await registry.register(PDFEngine())
        await registry.register(FFmpegEngine())
        return registry
    }
}

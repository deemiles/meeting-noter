// Mixes the .mov audio tracks into a 16 kHz mono WAV with per-track normalization.
// Usage: swift scripts/mix-wav.swift <in.mov> <out.wav> [track index]
import AVFoundation

let pcm16kMonoFloat: [String: Any] = [
    AVFormatIDKey: kAudioFormatLinearPCM,
    AVSampleRateKey: 16_000,
    AVNumberOfChannelsKey: 1,
    AVLinearPCMBitDepthKey: 32,
    AVLinearPCMIsFloatKey: true,
    AVLinearPCMIsNonInterleaved: false,
    AVLinearPCMIsBigEndianKey: false,
]

func samples(from sampleBuffer: CMSampleBuffer) -> [Float] {
    guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return [] }
    let length = CMBlockBufferGetDataLength(blockBuffer)
    var data = [Float](repeating: 0, count: length / 4)
    data.withUnsafeMutableBytes { ptr in
        _ = CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: ptr.baseAddress!)
    }
    return data
}

func trackPeak(asset: AVAsset, track: AVAssetTrack) throws -> Float {
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: pcm16kMonoFloat)
    reader.add(output)
    reader.startReading()
    var peak: Float = 0
    while let sampleBuffer = output.copyNextSampleBuffer() {
        for sample in samples(from: sampleBuffer) { peak = max(peak, abs(sample)) }
    }
    return peak
}

let args = CommandLine.arguments
guard args.count >= 3 else { fatalError("usage: mix-wav.swift <in.mov> <out.wav> [track#]") }
let inputURL = URL(fileURLWithPath: args[1])
let outputURL = URL(fileURLWithPath: args[2])
let onlyTrack: Int? = args.count > 3 ? Int(args[3]) : nil

let semaphore = DispatchSemaphore(value: 0)

Task {
    let asset = AVURLAsset(url: inputURL)
    var tracks = try await asset.loadTracks(withMediaType: .audio)
    if let onlyTrack { tracks = [tracks[onlyTrack - 1]] }
    precondition(!tracks.isEmpty, "no audio tracks")

    // Pass 1: each track's peak → its gain (normalize to 0.85, boost capped at 30x).
    var gains: [Float] = []
    for track in tracks {
        let peak = try trackPeak(asset: asset, track: track)
        let gain = peak > 0.001 ? min(0.85 / peak, 30) : 1
        gains.append(gain)
        print(String(format: "track: peak %.3f → gain %.2fx", peak, gain))
    }

    // Pass 2: streaming mix with a FIFO per track.
    final class TrackStream {
        let reader: AVAssetReader
        let output: AVAssetReaderTrackOutput
        let gain: Float
        var fifo: [Float] = []
        var finished = false

        init(asset: AVAsset, track: AVAssetTrack, gain: Float, settings: [String: Any]) throws {
            reader = try AVAssetReader(asset: asset)
            output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
            reader.add(output)
            reader.startReading()
            self.gain = gain
        }

        func fill(to count: Int) {
            while !finished && fifo.count < count {
                guard let sampleBuffer = output.copyNextSampleBuffer() else {
                    finished = true
                    break
                }
                fifo.append(contentsOf: samples(from: sampleBuffer))
            }
        }
    }

    let streams = try zip(tracks, gains).map {
        try TrackStream(asset: asset, track: $0, gain: $1, settings: pcm16kMonoFloat)
    }

    try? FileManager.default.removeItem(at: outputURL)
    let wavFile = try AVAudioFile(forWriting: outputURL, settings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
    ], commonFormat: .pcmFormatFloat32, interleaved: false)
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    let chunkSize = 16_000 * 10
    var totalWritten = 0
    while true {
        for stream in streams { stream.fill(to: chunkSize) }
        let available = streams.map(\.fifo.count).max() ?? 0
        if available == 0 { break }
        let length = min(available, chunkSize)

        var mix = [Float](repeating: 0, count: length)
        for stream in streams {
            let count = min(stream.fifo.count, length)
            for index in 0..<count {
                mix[index] += stream.fifo[index] * stream.gain
            }
            stream.fifo.removeFirst(count)
        }
        for index in 0..<length {
            mix[index] = max(-1, min(1, mix[index]))
        }

        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(length))!
        buffer.frameLength = AVAudioFrameCount(length)
        mix.withUnsafeBufferPointer { ptr in
            buffer.floatChannelData!.pointee.update(from: ptr.baseAddress!, count: length)
        }
        try wavFile.write(from: buffer)
        totalWritten += length
    }
    print(String(format: "wrote %.1f s → %@", Double(totalWritten) / 16_000, outputURL.lastPathComponent))
    semaphore.signal()
}

semaphore.wait()

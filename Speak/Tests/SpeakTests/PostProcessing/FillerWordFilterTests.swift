@testable import Speak
import Testing

private let filter = FillerWordFilter()
private let ctx = ProcessingContext(locale: .current)

private func filtered(_ text: String) async throws -> String {
    try await filter.apply(to: text, context: ctx)
}

// MARK: - Multi-word fillers

struct FillerWordFilterTests {
    // -- Multi-word fillers --

    @Test func `removes so yeah`() async throws {
        #expect(try await filtered("So yeah, the project is done.") == "The project is done.")
    }

    @Test func `removes you know`() async throws {
        #expect(try await filtered("The thing, you know, is broken.") == "The thing, is broken.")
    }

    @Test func `removes I mean`() async throws {
        #expect(try await filtered("I mean, it works fine.") == "It works fine.")
    }

    @Test func `removes sort of`() async throws {
        #expect(try await filtered("It sort of works.") == "It works.")
    }

    @Test func `removes kind of`() async throws {
        #expect(try await filtered("It kind of makes sense.") == "It makes sense.")
    }

    @Test func `removes uh huh`() async throws {
        #expect(try await filtered("Uh huh, that's right.") == "That's right.")
    }

    // -- "like" as filler --

    @Test func `removes like between commas`() async throws {
        #expect(try await filtered("The code, like, compiles.") == "The code, compiles.")
    }

    @Test func `removes like at sentence start`() async throws {
        #expect(try await filtered("Like, I don't know.") == "I don't know.")
    }

    @Test func `preserves like in normal usage`() async throws {
        #expect(try await filtered("I like this feature.") == "I like this feature.")
    }

    // -- Single-word fillers --

    @Test func `removes umm`() async throws {
        #expect(try await filtered("Umm let me think.") == "Let me think.")
    }

    @Test func `removes uhh`() async throws {
        #expect(try await filtered("Uhh I forgot.") == "I forgot.")
    }

    @Test func `removes um`() async throws {
        #expect(try await filtered("Um, the answer is yes.") == "The answer is yes.")
    }

    @Test func `removes uh`() async throws {
        #expect(try await filtered("Uh, maybe not.") == "Maybe not.")
    }

    @Test func `removes er`() async throws {
        #expect(try await filtered("Er, I think so.") == "I think so.")
    }

    @Test func `removes ah`() async throws {
        #expect(try await filtered("Ah, right.") == "Right.")
    }

    @Test func `removes hmm`() async throws {
        #expect(try await filtered("Hmm, interesting.") == "Interesting.")
    }

    @Test func `removes basically`() async throws {
        #expect(try await filtered("Basically, it works.") == "It works.")
    }

    // -- Sentence-start only fillers --

    @Test func `removes actually at start`() async throws {
        #expect(try await filtered("Actually, that's wrong.") == "That's wrong.")
    }

    @Test func `removes right at start`() async throws {
        #expect(try await filtered("Right, let's move on.") == "Let's move on.")
    }

    @Test func `removes so comma at start`() async throws {
        #expect(try await filtered("So, here's the plan.") == "Here's the plan.")
    }

    // -- Case insensitivity --

    @Test func `handles lowercase fillers`() async throws {
        #expect(try await filtered("um, the answer is yes.") == "The answer is yes.")
    }

    @Test func `handles uppercase fillers`() async throws {
        #expect(try await filtered("Um, the answer is yes.") == "The answer is yes.")
    }

    // -- Capitalization recovery --

    @Test func `recapitalizes after removal`() async throws {
        let result = try await filtered("Um, so yeah, the project works.")
        #expect(result.first?.isUppercase == true)
    }

    // -- Edge cases --

    @Test func `empty string passes through`() async throws {
        #expect(try await filtered("") == "")
    }

    @Test func `no fillers unchanged`() async throws {
        #expect(try await filtered("The quick brown fox.") == "The quick brown fox.")
    }

    @Test func `multiple fillers`() async throws {
        let result = try await filtered("Um, you know, basically it works.")
        #expect(!result.contains("Um"))
        #expect(!result.contains("you know"))
        #expect(!result.contains("basically"))
    }

    @Test func `filler with trailing punctuation`() async throws {
        #expect(try await filtered("Um. The answer is yes.") == "The answer is yes.")
    }

    @Test func `preserves mid sentence actually`() async throws {
        let result = try await filtered("I actually like it.")
        #expect(result.contains("actually"))
    }
}

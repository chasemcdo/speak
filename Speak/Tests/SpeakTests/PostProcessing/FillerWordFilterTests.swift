import Testing
@testable import Speak

private let filter = FillerWordFilter()
private let ctx = ProcessingContext(locale: .current)

private func filtered(_ text: String) async throws -> String {
    try await filter.apply(to: text, context: ctx)
}

// MARK: - Multi-word fillers

@Suite("FillerWordFilter")
struct FillerWordFilterTests {

    // -- Multi-word fillers --

    @Test func removesSoYeah() async throws {
        #expect(try await filtered("So yeah, the project is done.") == "The project is done.")
    }

    @Test func removesYouKnow() async throws {
        #expect(try await filtered("The thing, you know, is broken.") == "The thing, is broken.")
    }

    @Test func removesIMean() async throws {
        #expect(try await filtered("I mean, it works fine.") == "It works fine.")
    }

    @Test func removesSortOf() async throws {
        #expect(try await filtered("It sort of works.") == "It works.")
    }

    @Test func removesKindOf() async throws {
        #expect(try await filtered("It kind of makes sense.") == "It makes sense.")
    }

    @Test func removesUhHuh() async throws {
        #expect(try await filtered("Uh huh, that's right.") == "That's right.")
    }

    // -- "like" as filler --

    @Test func removesLikeBetweenCommas() async throws {
        #expect(try await filtered("The code, like, compiles.") == "The code, compiles.")
    }

    @Test func removesLikeAtSentenceStart() async throws {
        #expect(try await filtered("Like, I don't know.") == "I don't know.")
    }

    @Test func preservesLikeInNormalUsage() async throws {
        #expect(try await filtered("I like this feature.") == "I like this feature.")
    }

    // -- Single-word fillers --

    @Test func removesUmm() async throws {
        #expect(try await filtered("Umm let me think.") == "Let me think.")
    }

    @Test func removesUhh() async throws {
        #expect(try await filtered("Uhh I forgot.") == "I forgot.")
    }

    @Test func removesUm() async throws {
        #expect(try await filtered("Um, the answer is yes.") == "The answer is yes.")
    }

    @Test func removesUh() async throws {
        #expect(try await filtered("Uh, maybe not.") == "Maybe not.")
    }

    @Test func removesEr() async throws {
        #expect(try await filtered("Er, I think so.") == "I think so.")
    }

    @Test func removesAh() async throws {
        #expect(try await filtered("Ah, right.") == "Right.")
    }

    @Test func removesHmm() async throws {
        #expect(try await filtered("Hmm, interesting.") == "Interesting.")
    }

    @Test func removesBasically() async throws {
        #expect(try await filtered("Basically, it works.") == "It works.")
    }

    // -- Sentence-start only fillers --

    @Test func removesActuallyAtStart() async throws {
        #expect(try await filtered("Actually, that's wrong.") == "That's wrong.")
    }

    @Test func removesRightAtStart() async throws {
        #expect(try await filtered("Right, let's move on.") == "Let's move on.")
    }

    @Test func removesSoCommaAtStart() async throws {
        #expect(try await filtered("So, here's the plan.") == "Here's the plan.")
    }

    // -- Case insensitivity --

    @Test func handlesLowercaseFillers() async throws {
        #expect(try await filtered("um, the answer is yes.") == "The answer is yes.")
    }

    @Test func handlesUppercaseFillers() async throws {
        #expect(try await filtered("Um, the answer is yes.") == "The answer is yes.")
    }

    // -- Capitalization recovery --

    @Test func recapitalizesAfterRemoval() async throws {
        let result = try await filtered("Um, so yeah, the project works.")
        #expect(result.first?.isUppercase == true)
    }

    // -- Edge cases --

    @Test func emptyStringPassesThrough() async throws {
        #expect(try await filtered("") == "")
    }

    @Test func noFillersUnchanged() async throws {
        #expect(try await filtered("The quick brown fox.") == "The quick brown fox.")
    }

    @Test func multipleFillers() async throws {
        let result = try await filtered("Um, you know, basically it works.")
        #expect(!result.contains("Um"))
        #expect(!result.contains("you know"))
        #expect(!result.contains("basically"))
    }

    @Test func fillerWithTrailingPunctuation() async throws {
        #expect(try await filtered("Um. The answer is yes.") == "The answer is yes.")
    }

    @Test func preservesMidSentenceActually() async throws {
        let result = try await filtered("I actually like it.")
        #expect(result.contains("actually"))
    }
}

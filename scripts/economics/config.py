"""Pricing constants and configuration."""

# Last verified: 2026-04-16 from groq.com/pricing
PRICING_VERIFIED_DATE = "2026-04-16"
PRICING_STALE_DAYS = 90

WHISPER_COST_PER_HOUR = 0.04
WHISPER_COST_PER_MIN = WHISPER_COST_PER_HOUR / 60  # $0.000667/min

LLM_PRICING = {
    "llama-3.1-8b-instant": {
        "input_per_1m": 0.05,
        "output_per_1m": 0.08,
        "label": "Llama 3.1 8B (actual code)",
    },
    "llama-3.3-70b-versatile": {
        "input_per_1m": 0.59,
        "output_per_1m": 0.79,
        "label": "Llama 3.3 70B (documented)",
    },
}

DOCUMENTED_COST_PER_MIN = 0.00173

TIERS = {
    "free":  {"quota_min": 15,  "price_usd": 0.0,  "revenue_after_apple": 0.0},
    "basic": {"quota_min": 120, "price_usd": 5.99, "revenue_after_apple": 5.99 * 0.70},
    "pro":   {"quota_min": 500, "price_usd": 11.99, "revenue_after_apple": 11.99 * 0.70},
}

GROQ_BASE_URL = "https://api.groq.com/openai/v1"
WHISPER_MODEL = "whisper-large-v3-turbo"

# System prompts from SemanticCorrectionService.swift
SYSTEM_PROMPTS = {
    "terminal": (
        'Fix transcription errors in this terminal command dictation. '
        'Preserve CLI terms, flags, paths, and technical jargon exactly. '
        'Common corrections: "suit oh" -> "sudo", "see dee" -> "cd", '
        '"el es" -> "ls", "grip" -> "grep". '
        'Only fix obvious speech-to-text errors. Return corrected text only.'
    ),
    "coding": (
        'Fix transcription errors in this code-related dictation. '
        'Apply correct casing: camelCase, PascalCase, snake_case as appropriate. '
        'Common corrections: "a sink" -> "async", "you state" -> "useState", '
        '"con st" -> "const". '
        'Preserve code syntax and technical terms. Return corrected text only.'
    ),
    "chat": (
        'Lightly fix transcription errors in this chat message. '
        'Preserve informal tone, slang, and casual style. '
        'Fix only obvious speech recognition mistakes. '
        "Don't add formal punctuation. Return corrected text only."
    ),
    "email": (
        'Fix transcription errors in this email text. '
        'Apply proper grammar, punctuation, and professional tone. '
        'Preserve greetings and sign-offs. Return corrected text only.'
    ),
    "writing": (
        'Fix transcription errors in this text. '
        'Apply full grammar correction, proper punctuation, and capitalization. '
        "Maintain the author's intended meaning and style. "
        'Return corrected text only.'
    ),
    "general": (
        'Fix obvious transcription errors in this dictated text. '
        'Apply basic punctuation and capitalization. '
        'Preserve the original meaning. Return corrected text only.'
    ),
}

SAMPLE_TEXTS = {
    "terminal": [
        "sudo apt get install nginx",
        "cd projects slash my app and run npm install",
        "git checkout minus b feature slash authentication",
        "docker compose up minus d and then check the logs",
        "grep minus r TODO in the source directory",
        "pip install minus r requirements dot txt",
        "ssh user at server dot example dot com",
        "kubectl get pods minus n production",
        "curl minus X POST localhost colon 3000 slash api slash users",
        "chmod plus x deploy dot sh and then run it",
    ],
    "coding": [
        "create a new async function called fetch user data that takes a user ID parameter",
        "import react and use state from react then define a functional component",
        "the interface should have a name field of type string and an optional age of type number",
        "add a try catch block around the database query and log the error",
        "define a class called payment service that implements the payment provider interface",
        "use a for loop to iterate over the array and filter out null values",
        "the return type should be a promise of user array",
        "add a middleware function that checks the authorization header",
        "create an enum called status with values pending active and completed",
        "refactor this function to use async await instead of callbacks",
    ],
    "chat": [
        "hey can you check the pull request I just opened",
        "sounds good let's sync up tomorrow morning",
        "yeah that bug was tricky but I think the fix looks solid",
        "lol the tests are finally passing after three hours of debugging",
        "can you send me the figma link for the new design",
        "nice work on the migration it went super smooth",
        "I'll be out for lunch back in an hour",
        "did you see the new feature request from the product team",
        "thanks for the review I'll address the comments now",
        "heads up the staging server is down again",
    ],
    "email": [
        "Dear team, I wanted to provide an update on the quarterly roadmap. "
        "We have successfully completed three out of five milestones and are on track.",
        "Hi Sarah, thank you for your feedback on the proposal. "
        "I have incorporated your suggestions and attached the revised version.",
        "Please find attached the monthly performance report. "
        "Key highlights include a twenty percent increase in user engagement.",
        "I would like to schedule a meeting to discuss the upcoming product launch. "
        "Please let me know your availability for next week.",
        "Following up on our conversation yesterday, I have drafted the technical "
        "specification document. Could you please review sections three and four?",
    ],
    "writing": [
        "The implementation of the new authentication system requires careful consideration "
        "of both security and user experience. We need to balance strict validation with "
        "seamless login flows.",
        "After analyzing the performance metrics from the last quarter, several trends have "
        "emerged. The average response time has decreased by thirty percent.",
        "The migration strategy should follow a phased approach. In the first phase, we will "
        "set up the new infrastructure and run both systems in parallel.",
        "Documentation is a critical but often overlooked aspect of software development. "
        "Well-written documentation reduces onboarding time for new developers.",
        "The architecture decision to use microservices was driven by the need for independent "
        "deployment and scaling of different components.",
    ],
    "general": [
        "remind me to call the dentist tomorrow at two pm",
        "add milk eggs and bread to the shopping list",
        "the meeting with the design team is at three thirty in conference room B",
        "note to self review the budget proposal before Friday",
        "search for flights to San Francisco departing next Monday",
        "set a timer for twenty five minutes",
        "what's the weather forecast for this weekend",
        "play my focus playlist on Spotify",
        "the address is one two three main street apartment four B",
        "take a screenshot and save it to the desktop",
    ],
}

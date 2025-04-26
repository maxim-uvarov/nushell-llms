#!/usr/bin/env nu

# MIT LICENCE
#
# Copyright 2023 Gabin Lefranc, Maxim Uvarov
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

use utils.nu

def get-api [] {
    '/Users/user/git/nushell-openai/git-ignored-file'
    | if ($in | path exists) {
        open | decode base32hex | decode | str substring 1..
        | return $in
    }

    if not ("OPENAI_API_KEY" in $env) {
        error make {msg: "OPENAI_API_KEY not set"}
        exit 1
    }
    return $env.OPENAI_API_KEY
}
# Lists the OpenAI models
export def models [
    --model: string = '' # The model to retrieve
] {
    let suffix = if $model != "" { $"/($model)" }

    http get $"https://api.openai.com/v1/models($suffix)" -H ["Authorization" $"Bearer (get-api)"]
}

export-env {
    $env.OPENAI_DATA = {}
}

export def --env "set previous_messages" [messages: list] {
    $env.OPENAI_DATA = {
        previous_messages: $messages
    }
}
def --env "get previous_messages" [] {
    if ($env | get -i OPENAI_DATA) != null {
        if ($env.OPENAI_DATA | get -i previous_messages) != null {
            $env.OPENAI_DATA.previous_messages
        } else {
            []
        }
    } else {
        []
    }
}

# Helper function to add a parameter to a record if it's not null.
# Returns the original record with the new parameter added if value is not null.
def add_param [name: string, value: any] {
    if $value != null {
        upsert $name $value
    } else { }
}

# Chat completion API call that supports streaming responses.
# Makes a request to the OpenAI API and processes the streaming response line by line.
export def "api chat-completion" [
    model: string # ID of the model to use (e.g., "gpt-4").
    messages: list # List of message objects in the OpenAI format.
    --max-tokens: int # Maximum number of tokens in the generated completion.
    --temperature: number # Controls randomness (0-2, higher = more random).
    --top-p: number # Controls diversity via nucleus sampling (0-1).
    --n: int # Number of completions to generate per prompt.
    --stop: string # Sequences where the API will stop generating tokens.
    --frequency-penalty: number # Penalty for token repetition (-2.0 to 2.0).
    --presence-penalty: number # Penalty for new tokens (-2.0 to 2.0).
    --logit-bias: record # Modify likelihood of specific tokens appearing.
    --user: string # Unique identifier for the end-user making the request.
    --no-stream # Flag to disable streaming mode.
] {
    # Build the API request parameters, starting with required ones
    let request_params = {model: $model messages: $messages}
    | add_param "max_tokens" $max_tokens
    | add_param "temperature" $temperature
    | add_param "top_p" $top_p
    | add_param "n" $n
    | add_param "stop" $stop
    | add_param "frequency_penalty" $frequency_penalty
    | add_param "presence_penalty" $presence_penalty
    | add_param "logit_bias" $logit_bias
    | add_param "user" $user
    | add_param "stream" true # Default to streaming mode

    # Determine if we should use streaming based on flag and environment
    let is_streaming = not ($no_stream or ($nu.is-interactive == false))

    # Setup terminal for streaming display
    if $is_streaming {
        clear --keep-scrollback
        utils print-current-commandline # Show the command being executed
        print -n (ansi --escape "s") # Save cursor position for later restoration
    }

    # Make API call and process streaming response
    (
        http post "https://api.openai.com/v1/chat/completions"
        -H ["Authorization" $"Bearer (get-api)"]
        -t 'application/json'
        $request_params
    )
    | lines # Process the response line by line for streaming
    | each {|line|
        # Handle end of stream marker
        if $line == "data: [DONE]" {
            if $is_streaming {
                print -n $'(ansi --escape "u")(ansi --escape "J")' # Restore cursor position and clear line
            }
            return
        }

        # Process each data line from the stream
        $line
        | if ($in in ["\n" '']) { } else {
            # Skip empty lines
            str substring 6.. # Remove "data: " prefix
            | from json # Parse JSON
            | get choices.0.delta # Extract the delta content
            | if ($in | is-not-empty) { $in.content } # Get just the content if present
        }
        | if $is_streaming {
            tee { $'(ansi yellow)($in)(ansi reset)' | print -n } # Print in yellow while streaming
        } else { } # Otherwise just pass through for accumulation
    }
    | str join # Combine all content pieces
    | wrap response # Return as a record with 'response' field
}

export def 'ask' [
    ...input: string # The question to ask. If not provided, will use the input from the pipeline
    --model (-m): string = "gpt-4.1-mini" # The model to use, defaults to gpt-3.5-turbo
    --max-tokens: int = 4000 # The maximum number of tokens to generate, defaults to 150
    --system: string = "Answer my question as if you were an expert in the field."
    --temperature: float = 0.7
    --top_p: float = 1.0
    --quiet (-q) # don't output the results
    --no-stream
    --claude
] {
    let input = if $input == [] { } else { $input | str join "\n\n---\n\n" }
    let messages = [
        {"role": "system" "content": $system}
        {"role": "user" "content": $input}
    ]
    let result = if $claude {
        (
            api claude-completion $model $messages
            --temperature $temperature --top-p $top_p
            --max-tokens $max_tokens
            --no-stream=$no_stream
        )
    } else {
        (
            api chat-completion $model $messages
            --temperature $temperature --top-p $top_p
            --frequency-penalty 0
            --presence-penalty 0
            --max-tokens $max_tokens
            --no-stream=$no_stream
        )
    }

    # $result.response | print

    let content = $result.response
    | lines
    | str trim
    | str join "\n"

    {
        system: $system
        user: $input
        max-tokens: $max_tokens
        model: $model
    }
    | append $result
    | to yaml
    | save -ar ~/full_log.yaml

    {
        input: $input
        system: $system
        temperature: $temperature
        top-p: $top_p
        content: $content
    }
    | [$in]
    | to yaml
    | save -ar ~/short_log.yaml

    if not $quiet { $content }
}

export def "get-anthropic-api" [] {
    open /Users/user/git/nushell-openai/git-ignored-file2 | str substring 4.. | decode base64 | decode utf8 | $"nt-api03-e-($in)"
}

# Chat completion API call that supports streaming responses.
# Makes a request to the Anthropic Claude API and processes the streaming response line by line.
export def "api claude-completion" [
    model: string # ID of the model to use (e.g., "claude-3-7-sonnet-20250219").
    messages: list # List of message objects in the Anthropic format.
    --max-tokens: int = 4096 # Maximum number of tokens in the generated completion.
    --temperature: number # Controls randomness (0-1, higher = more random).
    --top-p: number = 0.2 # Controls diversity via nucleus sampling (0-1).
    --top-k: int = 1 # Limits sampling to top K options per token.
    --stop-sequences: list # Sequences where the API will stop generating tokens.
    --system: string # System prompt to send to Claude.
    --user: string # Unique identifier for the end-user making the request.
    --anthropic-version: string = "2023-06-01" # API version to use.
    --no-stream # Flag to disable streaming mode.
] {
    # Build the API request parameters, starting with required ones
    let request_params = {
        model: $model
        messages: $messages
        max_tokens: ($max_tokens | default 4096)
    }
    | add_param "temperature" $temperature
    | add_param "top_p" $top_p
    | add_param "top_k" $top_k
    | add_param "stop_sequences" $stop_sequences
    | add_param "system" $system
    | add_param "stream" true # Default to streaming mode

    # Determine if we should use streaming based on flag and environment
    let is_streaming = not ($no_stream or ($nu.is-interactive == false))

    # Setup terminal for streaming display
    if $is_streaming {
        clear --keep-scrollback
        utils print-current-commandline # Show the command being executed
        print -n (ansi --escape "s") # Save cursor position for later restoration
    }

    # Make API call and process streaming response
    (
        http post "https://api.anthropic.com/v1/messages"
        -H [
            "x-api-key"
            $"(get-anthropic-api)"
            "anthropic-version"
            $anthropic_version
            "content-type"
            "application/json"
        ]
        -t 'application/json'
        $request_params
    )
    | lines # Process the response line by line for streaming
    | each {|line|
        # Handle end of stream marker
        if $line == "data: [DONE]" {
            if $is_streaming {
                print -n $'(ansi --escape "u")(ansi --escape "J")' # Restore cursor position and clear line
            }
            return
        }

        # Process each data line from the stream
        $line
        | if ($in in ["\n" '']) { } else {
            # Skip empty lines
            if ($in starts-with "data: ") {
                str substring 6.. # Remove "data: " prefix
                | from json # Parse JSON
                | if ($in | get type) == "content_block_delta" {
                    # Check for content delta
                    if ($in | get delta.text | is-not-empty) {
                        $in.delta.text # Extract the delta text content
                    }
                } else { }
            } else { }
        }
        | if $is_streaming {
            tee { $'(ansi yellow)($in)(ansi reset)' | print -n } # Print in yellow while streaming
        } else { } # Otherwise just pass through for accumulation
    }
    | str join # Combine all content pieces
    | wrap response # Return as a record with 'response' field
}

###
# helpers unneded?
#
#

export def 'pu-add' [
    command: string
] {
    job spawn {
        (
            nu -c $"source /Users/user/apps-files/github/nushell-openai/openai.nu; ($command)"
            --config $nu.config-path --env-config $nu.env-path
        )
    }
    | null
}

# Make multiple prompts with parameters defined in YAML file
export def 'multiple_prompts' [
    prompt: string
    --config_file_path: string = '~/.alfred_llms_config.yaml'
] {
    open $config_file_path
    | each {|i|
        $i
        | items {|k v| [$'--($k)' $v] }
        | flatten
        | pu-add $"results_record '($prompt)' ($in | str join ' ')"
    }
}

export def 'bard_prompt' [
    prompt: string
    --temperature = 1.0
    --candidate_count = 1
] {
    (
        http post $"https://generativelanguage.googleapis.com/v1beta2/models/text-bison-001:generateText?key=($env.PALM_API_KEY)"
        -t 'application/json' {
            "prompt": {
                "text": $prompt
            }
            "temperature": $temperature
            "candidate_count": $candidate_count
        }
    )
    # (
    #     curl $"https://generativelanguage.googleapis.com/v1beta2/models/text-bison-001:generateText?key=($env.PALM_API_KEY)"
    #     -H 'Content-Type: application/json'
    #     -X POST
    #     -d '{
    #         "prompt": {
    #               "text": "Write a story about a magic backpack."
    #               },
    #         "temperature": 1.0,
    #         "candidate_count": 3}'
    # )
}

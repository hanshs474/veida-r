\name{veida_generate}
\alias{veida_generate}
\title{Generate an image from a prompt}
\usage{
veida_generate(prompt, aspect_ratio = "1:1", poll_seconds = 4, timeout_seconds = 240)
}
\arguments{
\item{prompt}{What to draw. Naming the light, the material and the composition moves the result far more than adding adjectives.}
\item{aspect_ratio}{One of "1:1", "16:9", "9:16", "4:3", "3:4".}
\item{poll_seconds}{How often the job is polled.}
\item{timeout_seconds}{Deadline for the whole call.}
}
\value{
A list with \code{url} (a permanent CDN link) and \code{watermarked}.
Failures signal a condition of class \code{veida_quota}, \code{veida_rejected},
\code{veida_timeout} or \code{veida_other}.
}
\description{
Calls the free anonymous tier of Veida (\url{https://veida.ai}): 4 credits per
client id, 4 per image, 30 per IP per day. Output is 1K and watermarked.
}
\examples{
\dontrun{
veida_generate("matte black ceramic mug on pale oak, soft window light")
}
}

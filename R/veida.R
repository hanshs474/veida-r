veida_base <- function() getOption("veida.base_url", "https://veida.ai")

veida_ratios <- c("1:1", "16:9", "9:16", "4:3", "3:4")

veida_anon_id <- function() {
  paste0("r-", paste(sprintf("%02x", sample(0:255, 8, replace = TRUE)), collapse = ""))
}

# Every failure carries a class to branch on: veida_quota (wait, or sign in),
# veida_rejected (reword the prompt), veida_timeout (retry).
veida_stop <- function(kind, msg) {
  stop(structure(class = c(paste0("veida_", kind), "veida_error", "error", "condition"),
                 list(message = paste("veida:", msg), call = NULL)))
}

veida_request <- function(url, id, body = NULL) {
  h <- new_handle()
  headers <- c("x-anon-id" = id, "User-Agent" = "veida-r/0.1.0")
  if (!is.null(body)) {
    headers <- c(headers, "Content-Type" = "application/json")
    handle_setopt(h, postfields = body)
  }
  handle_setheaders(h, .list = as.list(headers))
  handle_setopt(h, timeout = 60)
  res <- curl_fetch_memory(url, handle = h)
  env <- fromJSON(rawToChar(res$content), simplifyVector = FALSE)
  if (!identical(as.integer(env$code), 0L)) {
    veida_stop("other", if (is.null(env$message)) "request refused" else env$message)
  }
  env$data
}

# The quota wall answers 200 with code 0 and wall: true.
veida_parse_submit <- function(d) {
  if (isTRUE(d$wall)) {
    if (identical(d$reason, "anon_ip_daily")) {
      veida_stop("quota", "this machine has used its 30 free credits for today; sign in at https://veida.ai/pricing")
    }
    veida_stop("quota", "free allowance spent; sign in at https://veida.ai/pricing")
  }
  if (is.null(d$id) || !nzchar(d$id)) veida_stop("other", "the service returned no task id")
  d$id
}

# Status is not monotonic, so only a terminal failure ends the wait early.
veida_parse_poll <- function(p) {
  if (length(p$images)) {
    return(list(url = p$images[[1]],
                watermarked = length(p$watermarked) > 0 && isTRUE(p$watermarked[[1]])))
  }
  if (isTRUE(tolower(p$status) %in% c("failed", "error"))) {
    veida_stop("rejected", "the prompt was refused by the content filter; reword it")
  }
  NULL
}

#' Generate an image from a prompt
#'
#' Calls the free anonymous tier of Veida (\url{https://veida.ai}): 4 credits
#' per client id, 4 per image, 30 per IP per day. Output is 1K and watermarked.
#'
#' @param prompt What to draw. Naming the light, the material and the
#'   composition moves the result far more than adding adjectives.
#' @param aspect_ratio One of "1:1", "16:9", "9:16", "4:3", "3:4".
#' @param poll_seconds How often the job is polled.
#' @param timeout_seconds Deadline for the whole call.
#' @return A list with \code{url} (a permanent CDN link) and \code{watermarked}.
#'   Failures signal a condition of class \code{veida_quota},
#'   \code{veida_rejected}, \code{veida_timeout} or \code{veida_other}.
#' @examples
#' \dontrun{
#' veida_generate("matte black ceramic mug on pale oak, soft window light")
#' }
#' @export
veida_generate <- function(prompt, aspect_ratio = "1:1", poll_seconds = 4, timeout_seconds = 240) {
  if (!nzchar(trimws(prompt))) veida_stop("other", "prompt is required")
  if (!aspect_ratio %in% veida_ratios) {
    veida_stop("other", paste("aspect_ratio must be one of", paste(veida_ratios, collapse = ", ")))
  }
  id <- veida_anon_id()
  deadline <- Sys.time() + timeout_seconds
  d <- veida_request(paste0(veida_base(), "/api/ai/generate"), id,
                     toJSON(list(provider = "kie", mediaType = "image", model = "veida-image-v1",
                                 scene = "text-to-image", prompt = prompt,
                                 options = list(aspect_ratio = aspect_ratio)), auto_unbox = TRUE))
  task <- veida_parse_submit(d)
  query <- paste0(veida_base(), "/api/ai/anon-query?taskId=", curl_escape(task),
                  "&provider=kie&mediaType=image")
  repeat {
    if (Sys.time() > deadline) veida_stop("timeout", "still queued when the deadline passed")
    Sys.sleep(poll_seconds)
    # A dropped poll is not a failed job: keep going.
    p <- tryCatch(veida_request(query, id), veida_error = function(e) NULL, error = function(e) NULL)
    if (is.null(p)) next
    img <- veida_parse_poll(p)
    if (!is.null(img)) return(img)
  }
}

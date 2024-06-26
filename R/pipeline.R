#' Helper file to setup data
#'
#' @param location directory or list of urls containing x3p files.
#'          If there are sub-directories or sub-lists, this function will assume
#'          that each sub-directory contains lands from different bullets and
#'          will separate them accordingly
#' @param stop_at_step One of read, clean, crosscut, grooves, signatures
#' @param x3p_clean function to use to clean the x3p file - convert header info
#'          to correct units, rotate the surface matrix, etc.
#' @param ... additional arguments to cc_locate_grooves and cc_get_signature
#' @return a data_frame with bullet x3p files and processed data steps
#' @export
#' @importFrom dplyr mutate
#' @importFrom dplyr select
#' @importFrom dplyr bind_rows
#' @import assertthat
#' @importFrom dplyr "%>%"
bullet_pipeline <- function(location, stop_at_step = NULL,
                            x3p_clean = function(x) x, ...) {

  # Define variables to make CRAN happy
  bullet <- x3p <- cclist <- crosscut <- NULL
  ccdata <- glist <- grooves <- slist <- NULL

  if (is.null(stop_at_step)) stop_at_step <- "signatures"

  assert_that("function" %in% class(x3p_clean))
  assert_that(stop_at_step %in%
    c("read", "clean", "crosscut", "grooves", "signatures"))

  dots <- list(...)

  if (length(unlist(location)) > 1 | min(grepl("^(http|www)", location)) == 1) {
    land_list <- lapply(location, function(x) read_bullet(urllist = x)) %>%
      dplyr::bind_rows(.id = "bullet") %>%
      dplyr::select(source, bullet, x3p)
  } else {
    assert_that(dir.exists(location))

    dirfiles <- list.files(location,
      pattern = "x3p",
      full.names = T, recursive = T
    )
    dirs <- dirname(dirfiles) %>% unique()

    assert_that(length(dirfiles) > 0)
    land_list <- read_bullet(dirs) %>%
      # I don't know if this will work on Windows...
      dplyr::mutate(bullet = sub(
        pattern = "(.*)/(.*?)$", replacement = "\\2",
        dirname(as.character(source))
      )) %>%
      dplyr::select(source, bullet, x3p)
  }


  assert_that(
    has_name(land_list, "source"),
    has_name(land_list, "bullet"),
    has_name(land_list, "x3p")
  )
  lapply(land_list$x3p, function(x) assert_that("x3p" %in% class(x)))

  if (stop_at_step == "read") return(land_list)

  land_list <- land_list %>%
    dplyr::mutate(x3p = lapply(x3p, x3p_clean))

  if (stop_at_step == "clean") return(land_list)

  ccnames <- names(formals(x3p_crosscut_optimize))
  ccargs <- dots[names(dots) %in% ccnames]

  land_list <- land_list %>%
    dplyr::mutate(
      cclist = lapply(x3p, function(x) {
        ccargs$x3p <- x
        return(ccargs)
      }),
      crosscut = lapply(
        cclist,
        FUN = function(x) do.call("x3p_crosscut_optimize", x)
      ) %>% as.numeric()
    ) %>%
    dplyr::mutate(
      ccdata = lapply(
        1:length(x3p),
        function(i) x3p_crosscut(
            x3p[i][[1]],
            crosscut[i][[1]]
          )
      )
    ) %>%
    dplyr::select(-cclist)

  assert_that(
    has_name(land_list, "crosscut"),
    has_name(land_list, "ccdata")
  )

  if (stop_at_step == "crosscut") return(land_list)

  gnames <- names(formals(cc_locate_grooves))
  gargs <- dots[names(dots) %in% gnames]

  land_list <- land_list %>%
    dplyr::mutate(
      glist = lapply(ccdata, function(x) {
        gargs$ccdata <- x
        return(gargs)
      }),
      grooves = lapply(glist, function(.x) do.call("cc_locate_grooves", .x))
    ) %>%
    dplyr::select(-glist)

  assert_that(has_name(land_list, "grooves"))

  if (stop_at_step == "grooves") return(land_list)

  snames <- names(formals(cc_get_signature))
  sargs <- dots[names(dots) %in% snames]

  land_list <- land_list %>%
    dplyr::mutate(
      slist = lapply(1:length(x3p), function(i) {
        sargs$ccdata <- ccdata[i][[1]]
        sargs$grooves <- grooves[i][[1]]
        return(sargs)
      }),
      sigs = lapply(slist, function(.x) do.call("cc_get_signature", .x))
    ) %>%
    dplyr::select(-slist)

  assert_that(has_name(land_list, "sigs"))

  return(land_list)
}



#' Convert x3p header information to microns from meters
#'
#' @param x3p x3p data read in using read_x3p or read_bullet
#' @return x3p with header information in microns
#' @export
#' @import assertthat
x3pheader_to_microns <- function(x3p) {
  .Deprecated(msg = "Function x3pheader_to_microns is deprecated. Use x3p_scale_unit with scale_by=10^6 in package x3ptools instead")
  assert_that("x3p" %in% class(x3p))

  # make sure all measurements are in microns
  x3p$surface.matrix <- x3p$surface.matrix * 10^6
  x3p$header.info$incrementY <- x3p$header.info$incrementY * 10^6
  x3p$header.info$incrementX <- x3p$header.info$incrementX * 10^6
  x3p
}

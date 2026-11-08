# Standard CPM.cmake bootstrap: downloads a pinned CPM release into the build
# tree on first configure. See https://github.com/cpm-cmake/CPM.cmake
set(CPM_DOWNLOAD_VERSION 0.41.0)

if(CPM_SOURCE_CACHE)
  set(CPM_DOWNLOAD_LOCATION "${CPM_SOURCE_CACHE}/cpm/CPM_${CPM_DOWNLOAD_VERSION}.cmake")
elseif(DEFINED ENV{CPM_SOURCE_CACHE})
  set(CPM_DOWNLOAD_LOCATION "$ENV{CPM_SOURCE_CACHE}/cpm/CPM_${CPM_DOWNLOAD_VERSION}.cmake")
else()
  set(CPM_DOWNLOAD_LOCATION "${CMAKE_BINARY_DIR}/cmake/CPM_${CPM_DOWNLOAD_VERSION}.cmake")
endif()

if(NOT EXISTS ${CPM_DOWNLOAD_LOCATION})
  message(STATUS "Downloading CPM.cmake v${CPM_DOWNLOAD_VERSION} to ${CPM_DOWNLOAD_LOCATION}")
  file(
    DOWNLOAD
    https://github.com/cpm-cmake/CPM.cmake/releases/download/v${CPM_DOWNLOAD_VERSION}/CPM.cmake
    ${CPM_DOWNLOAD_LOCATION}
    STATUS CPM_DOWNLOAD_STATUS
    LOG CPM_DOWNLOAD_LOG
  )
  # file(DOWNLOAD) alone doesn't fail the configure on a bad response (e.g. a
  # GitHub release-CDN hiccup) -- it silently writes whatever came back
  # (possibly an empty/partial/error-page file) to CPM_DOWNLOAD_LOCATION, and
  # the NOT EXISTS guard above then never retries on a later configure since
  # that bad file is now sitting there. Check the status explicitly, delete
  # the bad file so the next configure gets a clean retry, and fail loudly
  # with the actual curl error instead of letting this surface later as a
  # confusing "Unknown CMake command CPMAddPackage".
  list(GET CPM_DOWNLOAD_STATUS 0 CPM_DOWNLOAD_STATUS_CODE)
  if(NOT CPM_DOWNLOAD_STATUS_CODE EQUAL 0)
    file(REMOVE ${CPM_DOWNLOAD_LOCATION})
    list(GET CPM_DOWNLOAD_STATUS 1 CPM_DOWNLOAD_STATUS_MESSAGE)
    message(FATAL_ERROR "Failed to download CPM.cmake v${CPM_DOWNLOAD_VERSION}: ${CPM_DOWNLOAD_STATUS_MESSAGE}\n${CPM_DOWNLOAD_LOG}")
  endif()
endif()

include(${CPM_DOWNLOAD_LOCATION})

package com.platformlab.backend;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Map;

import org.junit.jupiter.api.Test;

class StatusControllerTest {

    private final StatusController controller = new StatusController();

    @Test
    void statusShouldReportServiceAsUp() {
        Map<String, String> response = controller.status();

        assertThat(response.get("service")).isEqualTo("platform-lab-backend");
        assertThat(response.get("status")).isEqualTo("UP");
    }
}

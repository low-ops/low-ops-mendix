#!/usr/bin/env python3


import argparse
import requests
import json

import logging


logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)
import time


def main():
    parser = argparse.ArgumentParser(
        description="This script is used to call the unit test API of the mx-app"
    )
    parser.add_argument(
        "--app-ready-timeout",
        type=int,
        default=300,
        help="Timeout in seconds to wait for the app to be ready",
    )
    parser.add_argument(
        "--app-testing-timeout",
        type=int,
        default=300,
        help="Timeout in seconds to wait for the unit test to finish",
    )
    parser.add_argument(
        "--api-password", type=str, required=True, help="Password for the testing API"
    )
    parser.add_argument(
        "--app-url",
        type=str,
        required=False,
        default="http://localhost:8081",
        help="URL of the app",
    )
    parser.add_argument(
        "--json-file",
        type=str,
        required=False,
        default="results.json",
        help="Results file",
    )
    parser.add_argument(
        "--mode",
        type=str,
        required=False,
        default="default",
        help="Mode of the app; default or advanced",
    )

    args = parser.parse_args()

    if args.mode == "default":
        app_testing = AppTestingDefault(
            args.app_ready_timeout,
            args.app_testing_timeout,
            args.api_password,
            args.app_url,
            args.json_file,
        )
    else:
        app_testing = AppTestingAdvanced(
            args.app_ready_timeout,
            args.app_testing_timeout,
            args.api_password,
            args.app_url,
            args.json_file,
        )
    app_testing.run()
    with open(args.json_file, encoding="utf-8") as handle:
        payload = json.load(handle)
    failures = sum(
        int(suite.get("failures") or 0) for suite in payload.get("testsuites") or []
    )
    if failures:
        logger.error("Unit tests failed: %s failure(s)", failures)
        raise SystemExit(1)


"""
{
    "testsuites": [
        {
            "name": "TestSuite1",
            "tests": 2,
            "failures": 1,
            "skipped": 0,
            "time": 0.2,
            "testcases": [
                {
                    "name": "Test1",
                    "time": 0.1,
                    "failure": null,
                    "skipped": null,
                },
                {
                    "name": "Test2",
                    "time": 0.1,
                    "failure": {
                        "message": "Test failed",
                        "type": "AssertionError",
                    },
                    "skipped": {
                        "message": "Test skipped",
                    },
                }
            ]
        }
    
    ],
}
"""


class AppTestingBase:
    def __init__(
        self, app_ready_timeout, app_testing_timeout, api_password, app_url, json_file
    ):
        self.app_ready_timeout = app_ready_timeout
        self.app_testing_timeout = app_testing_timeout
        self.api_password = api_password
        self.app_url = app_url
        self.json_file = json_file

    def run(self):
        self._wait_for_app()
        self._start_unit_test()
        self._wait_for_unit_test()
        self._export_report()

    def _start_unit_test(self):
        raise NotImplementedError("This method must be implemented in the subclass")

    def _wait_for_unit_test(self):
        raise NotImplementedError("This method must be implemented in the subclass")

    def _wait_for_app(self):
        timeout_seconds = self.app_ready_timeout
        while timeout_seconds > 0:
            try:
                response = requests.get(self.app_url)
                if response.status_code == 200:
                    logger.info("App is ready")
                    break
            except requests.exceptions.RequestException:
                pass
            timeout_seconds -= 1
            if timeout_seconds == 0:
                logger.error("App did not start in time")
                exit(1)
            if timeout_seconds % 60 == 0:
                logger.info(f"Waiting for app to start. {timeout_seconds} seconds left")
            time.sleep(1)

    def _export_report(self):
        raise NotImplementedError("This method must be implemented in the subclass")


class AppTestingAdvanced(AppTestingBase):
    def __init__(
        self, app_ready_timeout, app_testing_timeout, api_password, app_url, json_file
    ):
        super().__init__(
            app_ready_timeout, app_testing_timeout, api_password, app_url, json_file
        )
        self.base_url = f"{app_url}/rest/unittest/v1"
        self.headers = {
            "Content-Type": "application/json",
            "Authorization": api_password,
        }

    def _start_unit_test(self):
        response = requests.post(
            f"{self.base_url}/execution/start", headers=self.headers
        )
        response.raise_for_status()
        logger.info("Unit test run started")

    def _wait_for_unit_test(self):
        finished = False
        timeout_seconds = self.app_testing_timeout
        while not finished:
            response = requests.get(
                f"{self.base_url}/execution/status", headers=self.headers
            )
            if response.status_code != 200:
                logger.error("Failed to get unit test status")
            try:
                response_json = response.json()
                if response_json.get("Status", None) == "Finished":
                    finished = True
            except Exception as e:
                logger.error("Failed to parse unit test status: " + str(e))
            if timeout_seconds == 0:
                logger.error("Unit test did not finish in time")
                exit(1)
            if timeout_seconds % 60 == 0:
                logger.info(
                    f"Waiting for unit test to finish. {timeout_seconds} seconds left"
                )
            timeout_seconds -= 1
            time.sleep(1)

    def _export_report(self):
        response = requests.get(
            f"{self.base_url}/applicationresult/latest", headers=self.headers
        )
        response.raise_for_status()
        logger.info(f"Results being exported to {self.json_file}")
        results = response.json()
        test_results = results.get("TestResults", [])
        test_suites = []
        for test_result in test_results:
            test_suite_name = test_result["Module"]
            test_suite_tests = 0
            test_suite_failures = 0
            test_suite_skipped = 0
            test_suite_time = 0
            test_suite_testcases = []

            for testcase in test_result.get("UTResults", []):
                description = testcase.get("Description", None)
                data_variation = testcase.get("DataVariationSequence", None)
                my_testcase_name = testcase["Name"]
                if description:
                    my_testcase_name = f"{my_testcase_name} ({description})"
                elif data_variation:
                    my_testcase_name = f"{my_testcase_name} ({data_variation})"
                try:
                    my_testcase_time = (
                        float(testcase["ReadableTime"].replace(" milliseconds", ""))
                        * 0.001
                    )
                except:
                    logger.warning(
                        f"Could not parse time for {my_testcase_name}: {testcase['ReadableTime']}"
                    )
                    my_testcase_time = 0
                my_testcase_skipped = None
                my_testcase_failure = None
                if testcase["Result"] == "_2_Failed":
                    test_suite_failures += 1
                    my_testcase_failure = {
                        "message": testcase.get(
                            "ResultMessage", str(testcase.get("AssertResults"))
                        ),
                        "type": "AssertionError",
                    }
                elif testcase["Result"] == "_1_Skipped":
                    test_suite_skipped += 1
                    my_testcase_skipped = {"message": "Test skipped"}
                my_testcase = {
                    "name": my_testcase_name,
                    "location": f"{test_suite_name}/microflows",
                    "time": my_testcase_time,
                    "failure": None,
                    "skipped": my_testcase_skipped,
                }
                if my_testcase_failure is not None:
                    message = my_testcase_failure.get("message") or "failed"
                    my_testcase["failure"] = {
                        "message": message,
                        "type": my_testcase_failure.get("type") or "AssertionError",
                        "content": message,
                    }
                test_suite_tests += 1
                test_suite_time += my_testcase_time
                test_suite_testcases.append(my_testcase)
            current_test_suite = {
                "name": test_suite_name,
                "tests": len(test_suite_testcases),
                "failures": test_suite_failures,
                "skipped": test_suite_skipped,
                "time": test_suite_time,
                "testcases": test_suite_testcases,
            }
            test_suites.append(current_test_suite)
        json.dump({"testsuites": test_suites}, open(self.json_file, "w"), indent=2)


class AppTestingDefault(AppTestingBase):
    def __init__(
        self, app_ready_timeout, app_testing_timeout, api_password, app_url, json_file
    ):
        super().__init__(
            app_ready_timeout, app_testing_timeout, api_password, app_url, json_file
        )
        self.base_url = f"{app_url}/unittests"
        self.auth = {
            "password": api_password,
        }

    def _start_unit_test(self):
        response = requests.post(f"{self.base_url}/start", json=self.auth)
        response.raise_for_status()
        logger.info("Unit test run started")

    def _wait_for_unit_test(self):
        finished = False
        timeout_seconds = self.app_testing_timeout
        while not finished:
            response = requests.post(f"{self.base_url}/status", json=self.auth)
            if response.status_code != 200:
                logger.error("Failed to get unit test status")
            try:
                response_json = response.json()
                if response_json.get("completed", False) == True:
                    finished = True
            except Exception as e:
                logger.error("Failed to parse unit test status: " + str(e))
            if timeout_seconds == 0:
                logger.error("Unit test did not finish in time")
                exit(1)
            if timeout_seconds % 60 == 0:
                logger.info(
                    f"Waiting for unit test to finish. {timeout_seconds} seconds left"
                )
            timeout_seconds -= 1
            time.sleep(1)

    def _export_report(self):
        response = requests.post(f"{self.base_url}/status", json=self.auth)
        response.raise_for_status()
        logger.info(f"Results being exported to {self.json_file}")
        results = response.json()
        failed_tests = results.get("failed_tests", [])
        passed_tests = results.get("passed_tests", [])
        """
        {
            "name": "MyFirstModule.UT_Test1",
            "step": "Starting microflow test 'MyFirstModule.UT_Test1'",
            "error": ""
        }
        """
        test_suites = []

        def add_testcase(test_result, failure):
            test_suite_name = test_result["name"].split(".")[0]

            my_test_suite = None
            for test_suite in test_suites:
                if test_suite["name"] == test_suite_name:
                    my_test_suite = test_suite
                    break
            if not my_test_suite:
                my_test_suite = {
                    "name": test_suite_name,
                    "tests": 0,
                    "failures": 0,
                    "skipped": 0,
                    "time": 0,
                    "testcases": [],
                }
                test_suites.append(my_test_suite)

            my_test_suite["tests"] += 1
            if failure is not None:
                my_test_suite["failures"] += 1

            short_name = test_result["name"].split(".")[-1]
            location = f"{test_suite_name}/microflows"
            case = {
                "name": short_name,
                "location": location,
                "time": 0,
                "failure": None,
                "skipped": None,
            }
            if failure is not None:
                message = failure.get("message") or "failed"
                case["failure"] = {
                    "message": message,
                    "type": failure.get("type") or "AssertionError",
                    "content": message,
                }
            my_test_suite["testcases"].append(case)

        for test_result in passed_tests:
            add_testcase(test_result, None)
        for test_result in failed_tests:
            add_testcase(
                test_result,
                {
                    "message": test_result["error"],
                    "type": test_result["step"],
                },
            )

        json.dump({"testsuites": test_suites}, open(self.json_file, "w"), indent=2)


if __name__ == "__main__":
    main()

import time
import unittest

from trippy.sources.batch import request_with_deadline


def successful_worker(values,ledger,chunk,connection):
    connection.send(('ok',{'mentions':[]}));connection.close()


def hanging_worker(values,ledger,chunk,connection):
    time.sleep(30)


class BatchDeadlineTests(unittest.TestCase):
    def test_completed_worker_returns_response(self):
        self.assertEqual(request_with_deadline({},'unused',{},timeout=10,worker=successful_worker),{'mentions':[]})

    def test_hanging_worker_has_a_real_total_deadline(self):
        start=time.monotonic()
        with self.assertRaisesRegex(ValueError,'wall deadline'):
            request_with_deadline({},'unused',{},timeout=0.3,worker=hanging_worker)
        self.assertLess(time.monotonic()-start,5)


if __name__=='__main__':unittest.main()

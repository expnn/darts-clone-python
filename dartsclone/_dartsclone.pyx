from libc.stdlib cimport malloc, free
import numpy as np
cimport numpy as np


cdef class TraverseState:
    def __init__(self, size_t node_pos=0, size_t key_pos=0, int result=0):
        self.key_pos = key_pos
        self.node_pos = node_pos
        self.result = result

    def __str__(self):
        return f"TraverseState(node_pos={self.node_pos}, key_pos={self.key_pos}, result={self.result})"

    def __repr__(self):
        return f"TraverseState({self.node_pos}, {self.key_pos}, {self.result})"

    def __copy__(self):
        return TraverseState(self.node_pos, self.key_pos, self.result)

    def __deepcopy__(self, memodict=None):
        return TraverseState(self.node_pos, self.key_pos, self.result)

    def copy_from(self, TraverseState other):
        self.key_pos = other.key_pos
        self.node_pos = other.node_pos
        self.result = other.result

    def set_node_from(self, TraverseState other):
        self.node_pos = other.node_pos
        self.key_pos = 0


cdef class DoubleArray:
    def __init__(self):
        self.__array = None

    def __cinit__(self):
        self.wrapped = new CppDoubleArray()
        assert sizeof(unsigned int) == self.unit_size(), "Unit size should be sizeof(unsigned int)"

    def __dealloc__(self):
        del self.wrapped

    def __getstate__(self):
        return self.array()

    def __setstate__(self, array):
        self.set_array(array)

    # def array(self):
    #     cdef size_t total_size = self.wrapped.total_size()
    #     cdef char[:] data = <char[:total_size]>self.wrapped.array()
    #     return bytes(data)
    #
    # def set_array(self, const unsigned char[::1] array, size_t size=0):
    #     self.wrapped.set_array(<const void*> &array[0], size)

    def array(self):
        cdef size_t size = self.wrapped.size()
        cdef unsigned int[:] data = <unsigned int[:size]>self.wrapped.array()
        return np.asarray(data)

    def set_array(self, unsigned int[::1] array, size_t size=0):
        if size <= 0:
            size = len(array)

        self.__array = array  # 避免被释放导致失效.
        self.wrapped.set_array(<const void*>&array[0], size)

    def clear(self):
        self.wrapped.clear()

    def unit_size(self):
        return self.wrapped.unit_size()

    def size(self):
        return self.wrapped.size()

    def total_size(self):
        return self.wrapped.total_size()

    def nonzero_size(self):
        return self.wrapped.nonzero_size()

    def build(self, keys,
              lengths = None,
              values = None):
        cdef size_t num_keys = len(keys)
        cdef const char** _keys = <const char**> malloc(num_keys * sizeof(char*))
        cdef size_t *_lengths = NULL
        cdef int *_values = NULL
        for i, key in enumerate(keys):
            _keys[i] = key
        if lengths is not None:
            _lengths = <size_t *> malloc(num_keys * sizeof(size_t))
            for i, length in enumerate(lengths):
                _lengths[i] = length
        if values is not None:
            _values = <int *> malloc(num_keys * sizeof(int))
            for i, value in enumerate(values):
                _values[i] = value
        try:
            self.wrapped.build(num_keys, _keys, <const size_t*> _lengths, <const int*> _values, NULL)
        finally:
            free(_keys)
            if lengths is not None:
                free(_lengths)
            if values is not None:
                free(_values)

    def open(self, file_name,
             mode = 'rb',
             size_t offset = 0,
             size_t size = 0):
        file_name = file_name.encode('utf-8')
        cdef const char *_file_name = file_name
        mode = mode.encode('utf-8')
        cdef const char *_mode = mode
        with nogil:
            self.wrapped.open(_file_name, _mode, offset, size)

    def save(self, file_name,
             mode = 'wb',
             size_t offset = 0):
        file_name = file_name.encode('utf-8')
        cdef const char *_file_name = file_name
        mode = mode.encode('utf-8')
        cdef const char *_mode = mode
        with nogil:
            self.wrapped.save(_file_name, _mode, offset)

    def exact_match_search(self, key,
                           size_t length = 0,
                           size_t node_pos = 0,
                           pair_type=True):
        cdef const char *_key = key
        if pair_type:
            return self.__exact_match_search_pair_type(_key, length, node_pos)
        else:
            return self.__exact_match_search(_key, length, node_pos)

    def common_prefix_search(self, key,
                             size_t max_num_results = 0,
                             size_t length = 0,
                             size_t node_pos = 0,
                             pair_type=True):
        cdef const char *_key = key
        if max_num_results == 0:
            max_num_results = len(key)
        if pair_type:
            return self.__common_prefix_search_pair_type(_key, max_num_results, length, node_pos)
        else:
            return self.__common_prefix_search(_key, max_num_results, length, node_pos)

    def traverse(self, TraverseState state,
                 key, size_t length = 0):
        cdef const char *_key = key
        cdef int result
        with nogil:
            result = self.wrapped.traverse(_key, state.node_pos, state.key_pos, length)
            state.result = result
        return result

    def __exact_match_search(self, const char *key,
                             size_t length = 0,
                             size_t node_pos = 0):
        cdef int result = -1
        with nogil:
            self.wrapped.exact_match_search(key, result, length, node_pos)
        return result

    def __exact_match_search_pair_type(self, const char *key,
                                            size_t length = 0,
                                            size_t node_pos = 0):
        cdef result_pair_type result
        with nogil:
            self.wrapped.exact_match_search(key, result, length, node_pos)
        return result.value, result.length

    def __common_prefix_search(self, const char *key,
                               size_t max_num_results,
                               size_t length,
                               size_t node_pos):
        cdef int *results = <int *> malloc(max_num_results * sizeof(int))
        cdef int result_len
        try:
            with nogil:
                result_len = self.wrapped.common_prefix_search(key, results, max_num_results, length, node_pos)
            values = list()
            for i in range(result_len):
                values.append(results[i])
        finally:
            free(results)
        return values

    def __common_prefix_search_pair_type(self, const char *key,
                                              size_t max_num_results,
                                              size_t length,
                                              size_t node_pos):
        cdef result_pair_type *results = <result_pair_type *> malloc(max_num_results * sizeof(result_pair_type))
        cdef result_pair_type result
        cdef int result_len
        try:
            with nogil:
                result_len = self.wrapped.common_prefix_search(key, results, max_num_results, length, node_pos)
            values = list()
            for i in range(result_len):
                result = results[i]
                values.append((result.value, result.length))
        finally:
            free(results)
        return values

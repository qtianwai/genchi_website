# 冒泡排序实现
# 冒泡排序是一种简单的排序算法，通过反复比较相邻元素并交换来排序

def bubble_sort(arr):
    """
    冒泡排序函数
    :param arr: 待排序的列表
    :return: 排序后的列表（原地排序，同时返回）
    """
    n = len(arr)

    for i in range(n):
        # 每轮结束后，最大的元素会"冒泡"到末尾
        # 所以每轮只需比较到 n-i-1
        for j in range(0, n - i - 1):
            # 如果前一个元素大于后一个，则交换
            if arr[j] > arr[j + 1]:
                arr[j], arr[j + 1] = arr[j + 1], arr[j]

    return arr


# 测试
if __name__ == "__main__":
    data = [64, 34, 25, 12, 22, 11, 90]
    print("排序前:", data)
    bubble_sort(data)
    print("排序后:", data)

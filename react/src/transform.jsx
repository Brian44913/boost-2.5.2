/* global BigInt */

var dateRegExp = /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/

// Iterative version to avoid stack overflow on large datasets (50k+ deals)
export function transformResponse(obj) {
    var stack = [{obj: obj, parent: null, key: null}]

    while (stack.length > 0) {
        var item = stack.pop()
        var val = item.obj

        if (val == null || typeof val !== 'object') {
            if (typeof val === 'string' && val.match(dateRegExp)) {
                var asDate = new Date(val)
                if (!isNaN(asDate.valueOf()) && item.parent && item.key != null) {
                    item.parent[item.key] = asDate
                }
            }
            continue
        }

        // BigInt conversion
        if (val.__typename === 'BigInt') {
            if (item.parent && item.key != null) {
                item.parent[item.key] = BigInt(val.n)
            }
            continue
        }

        for (var key in val) {
            if (val.hasOwnProperty(key)) {
                stack.push({obj: val[key], parent: val, key: key})
            }
        }
    }

    return obj
}

int count(char *str) {
    int c=0;
    char *p = str;
    while (*p != '\0')
    {
        c++;
        p++;
    }
    return c;
}